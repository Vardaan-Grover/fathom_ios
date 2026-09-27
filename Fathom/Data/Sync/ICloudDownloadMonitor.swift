import Combine
import Foundation

/// Watches the app's iCloud Drive container and publishes which books can be
/// opened on this device.
///
/// It does no file work itself. An `NSMetadataQuery` over the container fires
/// whenever an item appears, finishes downloading or finishes uploading; each
/// time, this asks `BookFileSync` for a reconciliation pass, and
/// `BookFileSync` reports the resulting readable set back through
/// `updateReadable(_:)`.
///
/// It publishes **only** `readableFilenames`, which changes about once per
/// file. Publishing per-file download progress re-rendered the whole home
/// screen hundreds of times a second while a library arrived.
@MainActor
final class ICloudDownloadMonitor: ObservableObject {

    static let shared = ICloudDownloadMonitor()

    /// Books that can be opened now — a local copy exists, or iCloud has the
    /// file fully downloaded.
    @Published private(set) var readableFilenames: Set<String> = []

    private var query: NSMetadataQuery?

    private init() {}

    // MARK: - Lifecycle

    /// Idempotent: a second call while a query is running does nothing. It
    /// used to start another query and register its observers again, leaking
    /// one per new iPad window or re-created scene.
    func start() {
        guard query == nil else { return }
        guard ICloudFileStore.shared.isAvailable else {
            AppLogger.log(tag: "ICloudDownloadMonitor", "iCloud unavailable — monitor not started")
            return
        }

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Everything in the container's Documents scope. A filename wildcard
        // is the predicate form iOS metadata queries reliably support; which
        // files matter is BookFileSync's business.
        q.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleQueryUpdate(_:)),
                           name: .NSMetadataQueryDidFinishGathering, object: q)
        center.addObserver(self, selector: #selector(handleQueryUpdate(_:)),
                           name: .NSMetadataQueryDidUpdate, object: q)

        q.start()
        query = q
        AppLogger.log(tag: "ICloudDownloadMonitor", "Query started")
    }

    func stop() {
        guard let q = query else { return }
        q.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
        query = nil
        AppLogger.log(tag: "ICloudDownloadMonitor", "Query stopped")
    }

    @objc private func handleQueryUpdate(_ notification: Notification) {
        BookFileSync.shared.scheduleReconcile()
    }

    // MARK: - Readable set

    func updateReadable(_ readable: Set<String>) {
        guard readable != readableFilenames else { return }
        readableFilenames = readable
    }

    /// `true` when the file can be opened by the reader.
    func isReadable(bookFilename filename: String?) -> Bool {
        guard let filename else { return false }
        if readableFilenames.contains(filename) { return true }
        // The set is refreshed asynchronously; a file imported a moment ago
        // may not be in it yet.
        return ICloudFileStore.shared.hasLocalCopy(BookFileRef(kind: .book, filename: filename))
    }

    /// Asks for a book to be brought onto this device, and returns
    /// immediately.
    func requestDownload(filename: String) {
        BookFileSync.shared.requestDownload(BookFileRef(kind: .book, filename: filename))
    }
}
