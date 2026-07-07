import Foundation
import ReadiumShared

/// Persists the last reading position (Readium locator JSON) per book.
///
/// Positions change on every page turn, so this store is built to make saves
/// cheap: all reads and writes go through an in-memory cache guarded by a
/// lock (it is hit from the main thread and from the SyncEngine actor), and
/// the backing JSON file is rewritten on a background queue, debounced.
/// `flush()` forces the pending write out — call it when the app leaves the
/// foreground so a force-quit can't lose more than the debounce window.
final class ReadingStateStore {
    static let shared = ReadingStateStore()

    /// Posted on the main queue after locally saved positions are flushed to
    /// disk (not posted for suppressed CloudKit pulls). Fires once per flush,
    /// not once per page turn. `userInfo["bookID"]` is the affected `UUID`.
    static let didSaveNotification = Notification.Name("ReadingStateStore.didSave")

    private static let writeDebounce: TimeInterval = 2.0

    private let saveURL: URL
    private let ioQueue = DispatchQueue(label: "com.fathom.readingstate.io", qos: .utility)

    // All fields below are guarded by `lock`.
    private let lock = NSLock()
    private var cache: [String: String]?          // bookID.uuidString → locator JSON
    private var isDirty = false                   // cache differs from disk
    private var booksAwaitingSyncNotification: Set<UUID> = []
    private var pendingWrite: DispatchWorkItem?

    private init() {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        saveURL = appSupport.appendingPathComponent("reading_state.json")
    }

    // MARK: - Locator read/write

    /// Saves the locator for a book. Cheap: updates the in-memory cache and
    /// schedules a debounced background disk write.
    /// - Parameter suppressSync: Pass `true` when applying a CloudKit pull so
    ///   the SyncEngine doesn't immediately push it back up.
    func saveLocator(_ locator: Locator, forBookID bookID: UUID, suppressSync: Bool = false) {
        guard let jsonString = locator.jsonString else { return }

        lock.lock()
        loadCacheIfNeededLocked()
        cache?[bookID.uuidString] = jsonString
        isDirty = true
        if !suppressSync { booksAwaitingSyncNotification.insert(bookID) }
        scheduleWriteLocked()
        lock.unlock()

        // Stamp the save time for CloudKit conflict resolution.
        UserDefaults.standard.set(Date(), forKey: savedAtKey(for: bookID))
    }

    func loadLocator(forBookID bookID: UUID) -> Locator? {
        guard let jsonString = locatorJSON(forBookID: bookID) else { return nil }
        return try? Locator(jsonString: jsonString)
    }

    func locatorJSON(forBookID bookID: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadCacheIfNeededLocked()
        return cache?[bookID.uuidString]
    }

    /// Writes any pending changes to disk immediately. Call when the app
    /// resigns active so a subsequent termination can't lose positions.
    func flush() {
        lock.lock()
        pendingWrite?.cancel()
        pendingWrite = nil
        lock.unlock()
        performWrite()
    }

    // MARK: - Timestamp (for CloudKit conflict resolution)

    func savedAt(forBookID bookID: UUID) -> Date? {
        UserDefaults.standard.object(forKey: savedAtKey(for: bookID)) as? Date
    }

    // MARK: - Private

    /// Must be called with `lock` held.
    private func loadCacheIfNeededLocked() {
        guard cache == nil else { return }
        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    /// Must be called with `lock` held.
    private func scheduleWriteLocked() {
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performWrite() }
        pendingWrite = work
        ioQueue.asyncAfter(deadline: .now() + Self.writeDebounce, execute: work)
    }

    private func performWrite() {
        lock.lock()
        pendingWrite = nil
        guard isDirty, let snapshot = cache else {
            lock.unlock()
            return
        }
        isDirty = false
        let toNotify = booksAwaitingSyncNotification
        booksAwaitingSyncNotification = []
        lock.unlock()

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: saveURL, options: .atomic)
        } catch {
            AppLogger.log(tag: "ReadingStateStore", "Failed to write reading state: \(error)")
        }

        guard !toNotify.isEmpty else { return }
        DispatchQueue.main.async {
            for bookID in toNotify {
                NotificationCenter.default.post(
                    name: Self.didSaveNotification,
                    object: nil,
                    userInfo: ["bookID": bookID]
                )
            }
        }
    }

    private func savedAtKey(for bookID: UUID) -> String {
        "fathom.reading_state.savedAt.\(bookID.uuidString)"
    }
}
