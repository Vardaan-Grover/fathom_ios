import Foundation
import Combine

// MARK: - Status

enum ICloudDownloadStatus: Equatable {
    /// File is fully available on this device.
    case local
    /// iCloud is downloading the file; 0–1 progress.
    case downloading(progress: Double)
    /// File exists in iCloud but has not been downloaded to this device.
    case notDownloaded
    /// iCloud is unavailable; treat the file as local (or absent).
    case iCloudUnavailable
}

// MARK: - Monitor

/// Tracks per-filename download state for EPUBs stored in the iCloud container.
///
/// Start the monitor after `ICloudFileStore.configure()` is called.
/// Stop it on sign-out.
///
/// This is a `@MainActor` `ObservableObject` so SwiftUI views can observe
/// `statusByFilename` directly.
@MainActor
final class ICloudDownloadMonitor: ObservableObject {

    static let shared = ICloudDownloadMonitor()

    /// Keyed by bare filename (e.g. "MyBook-UUID.epub").
    @Published private(set) var statusByFilename: [String: ICloudDownloadStatus] = [:]

    private var query: NSMetadataQuery?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard ICloudFileStore.shared.isAvailable else {
            AppLogger.log(tag: "ICloudDownloadMonitor", "iCloud unavailable — monitor not started")
            return
        }
        guard let booksDir = ICloudFileStore.shared.booksDirectory else { return }

        let q = NSMetadataQuery()
        // Search only the ubiquitous Documents scope (where our EPUBs live).
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Match every file under the user's books directory.
        q.predicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            NSMetadataItemPathKey,
            booksDir.path + "/"
        )
        // Sort by filename for stability (the dictionary doesn't need this, but
        // it keeps log output predictable during debugging).
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleQueryUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )
        center.addObserver(
            self,
            selector: #selector(handleQueryUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: q
        )

        q.start()
        query = q
        AppLogger.log(tag: "ICloudDownloadMonitor", "Query started for \(booksDir.lastPathComponent)/")
    }

    func stop() {
        query?.stop()
        if let q = query {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
        }
        query = nil
        statusByFilename = [:]
        AppLogger.log(tag: "ICloudDownloadMonitor", "Query stopped")
    }

    // MARK: - Query Handler

    @objc private func handleQueryUpdate(_ notification: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        var newStatus: [String: ICloudDownloadStatus] = [:]

        for item in (q.results as? [NSMetadataItem]) ?? [] {
            guard
                let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            let filename = (path as NSString).lastPathComponent
            let downloadingStatus = item.value(
                forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
            ) as? String
            let isDownloading = item.value(
                forAttribute: NSMetadataUbiquitousItemIsDownloadingKey
            ) as? Bool ?? false
            let rawProgress = item.value(
                forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey
            ) as? Double ?? 0.0

            if downloadingStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                newStatus[filename] = .local
            } else if isDownloading {
                newStatus[filename] = .downloading(progress: rawProgress / 100.0)
            } else {
                newStatus[filename] = .notDownloaded
            }
        }

        statusByFilename = newStatus
        AppLogger.log(tag: "ICloudDownloadMonitor", "Updated: \(newStatus.count) files tracked")
    }

    // MARK: - Convenience Accessors

    /// Returns the download status for a given filename.
    /// Falls back to `.iCloudUnavailable` when iCloud is off,
    /// and `.local` for covers / nil filenames (covers are always present).
    func status(forBook filename: String?) -> ICloudDownloadStatus {
        guard ICloudFileStore.shared.isAvailable else { return .iCloudUnavailable }
        guard let filename else { return .local }
        return statusByFilename[filename] ?? .notDownloaded
    }

    /// `true` when the file is available to be opened by the reader.
    func isReadable(bookFilename filename: String?) -> Bool {
        guard let filename else { return false }

        // iCloud unavailable → trust the local filesystem directly.
        guard ICloudFileStore.shared.isAvailable else {
            guard let url = ICloudFileStore.shared.bookURL(for: filename) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }

        switch statusByFilename[filename] {
        case .local:
            return true
        case .downloading, .notDownloaded, nil:
            // The file might have been downloaded between the last query refresh
            // and this call.  Check the filesystem as a final safety net.
            if let url = ICloudFileStore.shared.bookURL(for: filename) {
                var isDownloaded: AnyObject?
                _ = try? (url as NSURL).getResourceValue(&isDownloaded,
                    forKey: .ubiquitousItemDownloadingStatusKey)
                if let status = isDownloaded as? String,
                   status == URLUbiquitousItemDownloadingStatus.current.rawValue {
                    return true
                }
            }
            return false
        case .iCloudUnavailable:
            return true
        }
    }

    /// Requests iCloud to download a file and returns immediately.
    func requestDownload(filename: String) {
        ICloudFileStore.shared.startDownload(filename: filename)
    }
}
