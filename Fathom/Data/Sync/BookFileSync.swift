import Foundation
import GRDB

/// Keeps every referenced book file present on this device and mirrored in
/// iCloud Drive.
///
/// The book *records* sync through CloudKit; the *files* they point at —
/// EPUBs, covers, reflection images — travel through iCloud Drive. This type
/// reconciles the two sides for every file a record references:
///
/// | here | iCloud Drive | action |
/// |---|---|---|
/// | yes | no | upload: copy into the container |
/// | yes | yes, downloaded and uploaded | evict the container's local copy — ours is primary, so the file is not stored twice |
/// | no | yes, downloaded | copy it into local storage, then evict the container copy |
/// | no | yes, not downloaded | ask iCloud to download it (unless the reader removed it — see below) |
/// | no | no | nothing yet: the other device has not uploaded it |
///
/// That makes the library **always downloaded**, which is what a reading app
/// needs: iOS never evicts Application Support, so a book on the shelf opens
/// offline. The one exception is a book the reader chose to remove from this
/// device with "Remove Download"; it stays in iCloud and comes back when
/// opened.
///
/// It also covers the account cases. A new Apple ID has an empty container,
/// so every local file is uploaded into it — the library moves with the
/// reader. Files that lived only in the container (every file, before this
/// type existed) are copied down on first run.
///
/// Work runs on a private serial queue rather than an actor: copies of large
/// EPUBs block, and blocking an actor would tie up a thread of Swift's shared
/// cooperative pool.
nonisolated final class BookFileSync: @unchecked Sendable {

    static let shared = BookFileSync()

    private let queue = DispatchQueue(label: "com.fathom.book-file-sync", qos: .utility)

    // Everything below is touched only on `queue`.
    private var referenced: Set<BookFileRef> = []
    private var hasReferenceSnapshot = false
    private var observer: AnyDatabaseCancellable?
    private var reconcileScheduled = false

    private init() {}

    // MARK: - Lifecycle

    /// Starts following the database for referenced files, and reconciles.
    /// Safe to call again (after an iCloud identity change, say): it only
    /// schedules another pass.
    func start() {
        queue.async { [self] in
            if observer == nil {
                let observation = ValueObservation
                    .tracking { db in try Self.fetchReferenced(db) }
                    .removeDuplicates()
                observer = observation.start(
                    in: DatabaseManager.shared.dbQueue,
                    scheduling: .async(onQueue: queue),
                    onError: { error in
                        AppLogger.log(tag: "BookFileSync", "Reference observation failed: \(error)")
                    },
                    onChange: { [weak self] refs in
                        guard let self else { return }
                        referenced = refs
                        hasReferenceSnapshot = true
                        scheduleReconcileLocked(after: 0.3)
                    }
                )
            }
            scheduleReconcileLocked(after: 0.3)
        }
    }

    /// Asks for a reconciliation pass soon. Called when iCloud Drive reports
    /// changes — a download finished, an upload completed, a file appeared.
    func scheduleReconcile() {
        queue.async { [self] in scheduleReconcileLocked(after: 1.5) }
    }

    // MARK: - Reader-facing actions

    /// Fetches a file the reader wants now — a book being opened that is not
    /// on this device yet, or one they removed earlier.
    func requestDownload(_ ref: BookFileRef) {
        Self.clearOffloaded(ref.filename)
        queue.async { [self] in
            let store = ICloudFileStore.shared
            if let cloud = store.cloudURL(ref), store.cloudItemExists(cloud),
               !store.cloudItemIsDownloaded(cloud) {
                store.startDownloading(cloud)
            }
            scheduleReconcileLocked(after: 0.1)
        }
    }

    /// Whether a book can be removed from this device without losing it —
    /// that is, whether iCloud Drive holds an uploaded copy.
    func canRemoveDownload(_ ref: BookFileRef) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.isSafelyInCloud(ref))
            }
        }
    }

    /// Removes a book's local copy, leaving it in iCloud. Refuses — and
    /// returns false — when iCloud does not hold an uploaded copy, because
    /// then the local copy is the only one.
    func removeDownload(_ ref: BookFileRef) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard Self.isSafelyInCloud(ref), let local = ICloudFileStore.shared.localURL(ref) else {
                    continuation.resume(returning: false)
                    return
                }
                Self.markOffloaded(ref.filename)
                do {
                    try FileManager.default.removeItem(at: local)
                } catch {
                    AppLogger.log(tag: "BookFileSync", "Remove download failed: \(error)")
                }
                publishReadableLocked()
                continuation.resume(returning: true)
            }
        }
    }

    // MARK: - Reconciliation

    private func scheduleReconcileLocked(after delay: TimeInterval) {
        guard !reconcileScheduled else { return }
        reconcileScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            reconcileScheduled = false
            reconcileLocked()
        }
    }

    private func reconcileLocked() {
        // Until the first snapshot arrives, "nothing referenced" is unknown,
        // not empty.
        guard hasReferenceSnapshot else { return }

        let store = ICloudFileStore.shared
        guard store.isAvailable else {
            publishReadableLocked()
            return
        }

        let offloaded = Self.offloadedSet()
        var uploaded = 0, downloaded = 0, requested = 0, evicted = 0, waiting = 0

        for ref in referenced {
            guard let cloud = store.cloudURL(ref), let local = store.localURL(ref) else { continue }
            let hasLocal = FileManager.default.fileExists(atPath: local.path)
            let inCloud = store.cloudItemExists(cloud)

            switch (hasLocal, inCloud) {
            case (true, false):
                if store.coordinatedCopy(from: local, to: cloud) { uploaded += 1 }

            case (true, true):
                if store.cloudItemIsDownloaded(cloud), store.cloudItemIsUploaded(cloud) {
                    store.evict(cloud)
                    evicted += 1
                }

            case (false, true):
                if ref.kind == .book, offloaded.contains(ref.filename) { continue }
                if store.cloudItemIsDownloaded(cloud) {
                    if store.coordinatedCopy(from: cloud, to: local) {
                        downloaded += 1
                        store.evict(cloud)
                    }
                } else {
                    store.startDownloading(cloud)
                    requested += 1
                }

            case (false, false):
                waiting += 1
            }
        }

        publishReadableLocked()

        if uploaded + downloaded + requested + evicted > 0 {
            AppLogger.log(tag: "BookFileSync",
                          "files: uploaded \(uploaded), copied down \(downloaded), "
                          + "downloading \(requested), evicted \(evicted), not in iCloud yet \(waiting)")
        }
    }

    /// Tells the UI which books can be opened right now.
    private func publishReadableLocked() {
        let store = ICloudFileStore.shared
        let readable = Set(referenced.lazy
            .filter { $0.kind == .book }
            .filter { ref in
                if store.hasLocalCopy(ref) { return true }
                guard let cloud = store.cloudURL(ref) else { return false }
                return store.cloudItemIsDownloaded(cloud)
            }
            .map(\.filename))
        Task { @MainActor in
            ICloudDownloadMonitor.shared.updateReadable(readable)
        }
    }

    private static func isSafelyInCloud(_ ref: BookFileRef) -> Bool {
        let store = ICloudFileStore.shared
        guard let cloud = store.cloudURL(ref) else { return false }
        return store.cloudItemExists(cloud) && store.cloudItemIsUploaded(cloud)
    }

    // MARK: - References

    /// Every file a record on this device points at.
    static func fetchReferenced(_ db: Database) throws -> Set<BookFileRef> {
        var refs = Set<BookFileRef>()
        for row in try Row.fetchAll(db, sql: "SELECT localFilename, coverFilename FROM books") {
            if let name: String = row["localFilename"], !name.isEmpty {
                refs.insert(BookFileRef(kind: .book, filename: name))
            }
            if let name: String = row["coverFilename"], !name.isEmpty {
                refs.insert(BookFileRef(kind: .cover, filename: name))
            }
        }
        let reflections = try String.fetchAll(db, sql: """
            SELECT reflectionImageFilename FROM bookCompletions
            WHERE reflectionImageFilename IS NOT NULL AND reflectionImageFilename <> ''
            """)
        for name in reflections {
            refs.insert(BookFileRef(kind: .reflection, filename: name))
        }
        return refs
    }

    // MARK: - Offloaded books
    //
    // Books the reader removed from this device. Kept in UserDefaults because
    // it is a per-device preference, not library data.

    private static let offloadedKey = "fathom.offloadedBookFiles"

    static func offloadedSet() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: offloadedKey) ?? [])
    }

    static func isOffloaded(_ filename: String) -> Bool {
        offloadedSet().contains(filename)
    }

    static func markOffloaded(_ filename: String) {
        var set = offloadedSet()
        set.insert(filename)
        UserDefaults.standard.set(Array(set), forKey: offloadedKey)
    }

    static func clearOffloaded(_ filename: String) {
        var set = offloadedSet()
        guard set.remove(filename) != nil else { return }
        UserDefaults.standard.set(Array(set), forKey: offloadedKey)
    }

    static func forgetOffloaded(_ refs: [BookFileRef]) {
        var set = offloadedSet()
        let before = set.count
        for ref in refs { set.remove(ref.filename) }
        guard set.count != before else { return }
        UserDefaults.standard.set(Array(set), forKey: offloadedKey)
    }
}
