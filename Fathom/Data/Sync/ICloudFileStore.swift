import Foundation
import os

/// The kinds of file a book carries, and where each lives.
nonisolated enum BookFileKind: String, CaseIterable, Sendable {
    case book
    case cover
    case reflection

    /// The directory name, locally and in the iCloud container alike.
    var directoryName: String {
        switch self {
        case .book:       return "Books"
        case .cover:      return "Covers"
        case .reflection: return "Reflections"
        }
    }
}

/// One file a book record points at.
nonisolated struct BookFileRef: Hashable, Sendable {
    let kind: BookFileKind
    let filename: String
}

/// Paths and file operations for EPUBs, covers and reflection images.
///
/// **Local first.** Every file's primary copy lives in Application Support on
/// this device — `Books/`, `Covers/`, `Reflections/` — and that is the copy the
/// app reads. iOS never evicts Application Support, so a book on the shelf
/// always opens, offline, and survives signing out of iCloud or switching
/// Apple ID.
///
/// **iCloud Drive is the transport.** Each local file is mirrored into the
/// app's ubiquity container (`<container>/Documents/<Kind>/`) so other
/// devices can fetch it. Once a mirrored copy has uploaded, its local
/// materialisation is evicted, so a file does not take up space twice.
/// `BookFileSync` runs that reconciliation; this type provides the paths and
/// the coordinated primitives.
///
/// Files previously lived *only* in the container, where iOS could evict them
/// under storage pressure and signing out removed them. `BookFileSync` copies
/// any such file into local storage on first run.
///
/// **Deliberately `nonisolated`.** `SWIFT_DEFAULT_ACTOR_ISOLATION` is MainActor,
/// so an unannotated type would be a main-actor type, and callers off the main
/// thread would hop back onto it for file I/O. `MainActorIsolationTests` pins
/// this down.
nonisolated final class ICloudFileStore: Sendable {

    static let shared = ICloudFileStore()

    static let containerIdentifier = "iCloud.com.Vardaan.Fathom"

    /// The resolved ubiquity container, or nil when iCloud Drive is
    /// unavailable. Re-resolved when the iCloud identity changes.
    private let container = OSAllocatedUnfairLock<URL?>(initialState: nil)

    private init() {}

    // MARK: - Lifecycle

    /// Resolves the iCloud container and prepares its directories. Safe to
    /// call again — `ICloudIdentityObserver` does so when the signed-in
    /// Apple ID changes.
    ///
    /// `url(forUbiquityContainerIdentifier:)` does real I/O (~870ms on a clean
    /// install); never call this on the main thread.
    func configure() {
        let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier)
        container.withLock { $0 = url }

        if url == nil {
            AppLogger.log(tag: "ICloudFileStore", "iCloud Drive unavailable — files stay local")
        } else {
            AppLogger.log(tag: "ICloudFileStore", "iCloud container resolved")
        }

        for kind in BookFileKind.allCases {
            createDirectory(localDirectory(kind))
            createDirectory(cloudDirectory(kind))
        }
    }

    var isAvailable: Bool { containerURL != nil }
    var containerURL: URL? { container.withLock { $0 } }

    // MARK: - Directories

    /// Where a kind's primary, always-present copies live.
    func localDirectory(_ kind: BookFileKind) -> URL? {
        AppFiles.applicationSupportDirectory()
            .appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    /// Where a kind's mirrored copies live in iCloud Drive, or nil when
    /// iCloud Drive is unavailable.
    func cloudDirectory(_ kind: BookFileKind) -> URL? {
        guard let container = containerURL else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    /// Kept for callers that size or list the covers on this device.
    var coversDirectory: URL? { localDirectory(.cover) }

    func localURL(_ ref: BookFileRef) -> URL? {
        localDirectory(ref.kind)?.appendingPathComponent(ref.filename)
    }

    func cloudURL(_ ref: BookFileRef) -> URL? {
        cloudDirectory(ref.kind)?.appendingPathComponent(ref.filename)
    }

    // MARK: - Resolution

    /// The URL to read a file from: the local copy when it exists, otherwise
    /// the iCloud copy (reading it makes iCloud fetch it), otherwise the local
    /// path the file will arrive at.
    func url(for ref: BookFileRef) -> URL? {
        if let local = localURL(ref), FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        if let cloud = cloudURL(ref), cloudItemExists(cloud) {
            return cloud
        }
        return localURL(ref)
    }

    func bookURL(for filename: String) -> URL? {
        url(for: BookFileRef(kind: .book, filename: filename))
    }

    func coverURL(for filename: String) -> URL? {
        url(for: BookFileRef(kind: .cover, filename: filename))
    }

    func reflectionImageURL(for filename: String) -> URL? {
        url(for: BookFileRef(kind: .reflection, filename: filename))
    }

    /// Whether this device holds its own copy of the file.
    func hasLocalCopy(_ ref: BookFileRef) -> Bool {
        guard let url = localURL(ref) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Writes (local only — BookFileSync mirrors them)

    /// Copies an EPUB into local storage and returns its URL. Not mirrored to
    /// iCloud until a book record references it, so a cancelled import never
    /// uploads anything.
    func copyBook(from sourceURL: URL) throws -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let filename = "\(baseName)-\(UUID().uuidString).\(ext)"
        let destURL = try requireLocalDirectory(.book).appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        AppLogger.log(tag: "ICloudFileStore", "Book copied → \(filename)")
        return destURL
    }

    /// Saves cover image data and returns the filename.
    func saveCover(_ data: Data, coverID: UUID) throws -> String {
        let filename = "\(coverID.uuidString).png"
        try data.write(to: requireLocalDirectory(.cover).appendingPathComponent(filename),
                       options: .atomic)
        return filename
    }

    /// Saves reflection image data (JPEG) and returns the filename.
    func saveReflectionImage(_ data: Data, imageID: UUID = UUID()) throws -> String {
        let filename = "\(imageID.uuidString).jpg"
        try data.write(to: requireLocalDirectory(.reflection).appendingPathComponent(filename),
                       options: .atomic)
        return filename
    }

    /// Deletes files everywhere: this device and iCloud Drive, which removes
    /// them from the reader's other devices too.
    func delete(_ refs: [BookFileRef]) {
        for ref in refs {
            if let local = localURL(ref), FileManager.default.fileExists(atPath: local.path) {
                do {
                    try FileManager.default.removeItem(at: local)
                } catch {
                    AppLogger.log(tag: "ICloudFileStore", "Could not delete \(ref.filename): \(error)")
                }
            }
            if let cloud = cloudURL(ref), cloudItemExists(cloud) {
                coordinatedDelete(cloud)
            }
        }
        BookFileSync.forgetOffloaded(refs)
    }

    func deleteFiles(bookFilename: String?, coverFilename: String?, reflectionFilename: String?) {
        var refs: [BookFileRef] = []
        if let bookFilename { refs.append(BookFileRef(kind: .book, filename: bookFilename)) }
        if let coverFilename { refs.append(BookFileRef(kind: .cover, filename: coverFilename)) }
        if let reflectionFilename {
            refs.append(BookFileRef(kind: .reflection, filename: reflectionFilename))
        }
        delete(refs)
    }

    // MARK: - iCloud item state

    /// Whether iCloud Drive holds the item, downloaded or not. A file that
    /// has not been downloaded may appear as a `.<name>.icloud` placeholder
    /// rather than at its own path.
    func cloudItemExists(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.path) || fm.fileExists(atPath: placeholderURL(for: url).path)
    }

    func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    /// Whether the iCloud copy is fully present on this device.
    func cloudItemIsDownloaded(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        else { return false }
        return values.ubiquitousItemDownloadingStatus == .current
    }

    /// Whether the iCloud copy has reached the server. An item that is not
    /// materialised here came *from* the server, so it counts as uploaded.
    func cloudItemIsUploaded(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return cloudItemExists(url)
        }
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey])
        return values?.ubiquitousItemIsUploaded ?? false
    }

    // MARK: - Coordinated primitives
    //
    // Files in a ubiquity container are shared with the iCloud daemon, so every
    // read and write goes through NSFileCoordinator, as Apple requires.

    /// Copies `source` to `destination`, replacing anything there.
    @discardableResult
    func coordinatedCopy(from source: URL, to destination: URL) -> Bool {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: source, options: [],
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { readURL, writeURL in
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: writeURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                // Copy beside the destination, then swap in: a reader never
                // sees a half-written file.
                let temp = writeURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(UUID().uuidString).partial")
                try fm.copyItem(at: readURL, to: temp)
                if fm.fileExists(atPath: writeURL.path) {
                    _ = try fm.replaceItemAt(writeURL, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: writeURL)
                }
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            AppLogger.log(tag: "ICloudFileStore",
                          "Copy \(source.lastPathComponent) failed: \(error)")
            return false
        }
        return true
    }

    func coordinatedDelete(_ url: URL) {
        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinationError
        ) { writeURL in
            do {
                try FileManager.default.removeItem(at: writeURL)
            } catch {
                deleteError = error
            }
        }
        if let error = coordinationError ?? deleteError {
            AppLogger.log(tag: "ICloudFileStore",
                          "Delete \(url.lastPathComponent) from iCloud failed: \(error)")
        }
    }

    func startDownloading(_ url: URL) {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            AppLogger.log(tag: "ICloudFileStore",
                          "Download request failed for \(url.lastPathComponent): \(error)")
        }
    }

    /// Drops the local materialisation of an iCloud item; the item stays in
    /// iCloud. Used once the primary copy is safely local.
    func evict(_ url: URL) {
        do {
            try FileManager.default.evictUbiquitousItem(at: url)
        } catch {
            AppLogger.log(tag: "ICloudFileStore",
                          "Evict \(url.lastPathComponent) failed: \(error)")
        }
    }

    // MARK: - Private

    private func requireLocalDirectory(_ kind: BookFileKind) throws -> URL {
        guard let dir = localDirectory(kind) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createDirectory(_ url: URL?) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            AppLogger.log(tag: "ICloudFileStore",
                          "Failed to create \(url.lastPathComponent): \(error)")
        }
    }
}
