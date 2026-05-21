import Foundation

/// Manages all file paths and write operations for books and covers.
///
/// When iCloud is available (user signed into iCloud and entitlement present),
/// files live inside the app's ubiquity container, scoped by Supabase user ID:
///   <iCloudContainer>/Documents/Books/<userID>/<filename>
///   <iCloudContainer>/Documents/Covers/<userID>/<filename>
///
/// When iCloud is unavailable the store falls back to ApplicationSupportDirectory,
/// preserving the original layout so existing users lose nothing.
///
/// Call `configure(userID:)` immediately after Supabase sign-in and
/// `reset()` on sign-out.  All other call sites just use the shared instance.
final class ICloudFileStore {

    static let shared = ICloudFileStore()

    // MARK: - State (written only on the main queue via configure/reset)

    private var _userID: UUID?
    private var _containerURL: URL?   // nil → iCloud unavailable

    private init() {}

    // MARK: - Lifecycle

    /// Resolves the iCloud container and prepares user-scoped directories.
    /// Must be called before any book is imported or opened.
    func configure(userID: UUID) {
        _userID = userID

        // url(forUbiquityContainerIdentifier:) can do I/O — call from a background thread.
        // We do it here synchronously only because it is called from the auth listener
        // (already off the main actor) and the result is tiny.
        _containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.Vardaan.Fathom"
        )

        if _containerURL == nil {
            AppLogger.log(tag: "ICloudFileStore", "iCloud unavailable — using local storage")
        } else {
            AppLogger.log(tag: "ICloudFileStore", "iCloud container resolved for user \(userID)")
        }

        // Eagerly create user directories so they are ready for the migrator.
        createDirectoriesIfNeeded()
    }

    /// Tears down iCloud state on sign-out.
    func reset() {
        _userID = nil
        _containerURL = nil
    }

    var isAvailable: Bool { _containerURL != nil && _userID != nil }
    var userID: UUID? { _userID }
    var containerURL: URL? { _containerURL }

    // MARK: - Directory URLs

    /// iCloud path for EPUB files belonging to the current user.
    /// `nil` when iCloud is unavailable.
    var booksDirectory: URL? {
        guard let container = _containerURL, let uid = _userID else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(uid.uuidString, isDirectory: true)
    }

    /// iCloud path for cover images belonging to the current user.
    var coversDirectory: URL? {
        guard let container = _containerURL, let uid = _userID else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Covers", isDirectory: true)
            .appendingPathComponent(uid.uuidString, isDirectory: true)
    }

    // MARK: - URL Resolution

    /// Resolves the best available URL for an EPUB filename.
    ///
    /// Priority:
    ///  1. iCloud container path (present whether downloaded or not — use
    ///     ICloudDownloadMonitor to know the actual download state)
    ///  2. Legacy local path (ApplicationSupportDirectory/Books/) — used during
    ///     the brief window before migration completes on first launch.
    func bookURL(for filename: String) -> URL? {
        if let dir = booksDirectory {
            let icloudURL = dir.appendingPathComponent(filename)
            // If the iCloud slot already exists (downloaded or placeholder), use it.
            // Otherwise fall back to local so the app still works mid-migration.
            if FileManager.default.fileExists(atPath: icloudURL.path) {
                return icloudURL
            }
            if let localURL = legacyLocalBooksDirectory?.appendingPathComponent(filename),
               FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
            // File hasn't been migrated yet (or is incoming from another device).
            // Return the iCloud URL so the caller can trigger a download.
            return icloudURL
        }
        // iCloud unavailable — local only
        return legacyLocalBooksDirectory?.appendingPathComponent(filename)
    }

    /// Resolves the best available URL for a cover image filename.
    func coverURL(for filename: String) -> URL? {
        if let dir = coversDirectory {
            let icloudURL = dir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: icloudURL.path) {
                return icloudURL
            }
            if let localURL = legacyLocalCoversDirectory?.appendingPathComponent(filename),
               FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
            return icloudURL
        }
        return legacyLocalCoversDirectory?.appendingPathComponent(filename)
    }

    // MARK: - Write Operations

    /// Copies an EPUB from a security-scoped or temporary URL into the store.
    /// Returns the destination URL (used by the caller to extract metadata, etc.)
    func copyBook(from sourceURL: URL) throws -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let filename = "\(baseName)-\(UUID().uuidString).\(ext)"
        let destDir = try effectiveBooksDirectory()
        let destURL = destDir.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        AppLogger.log(tag: "ICloudFileStore", "Book copied → \(filename)")
        return destURL
    }

    /// Saves raw cover image data and returns the filename.
    func saveCover(_ data: Data, coverID: UUID) throws -> String {
        let filename = "\(coverID.uuidString).png"
        let destDir = try effectiveCoversDirectory()
        try data.write(to: destDir.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    /// Asks iCloud to download an EPUB that exists in the container but is not
    /// yet available locally.
    func startDownload(filename: String) {
        guard let url = booksDirectory?.appendingPathComponent(filename) else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            AppLogger.log(tag: "ICloudFileStore", "Download requested for \(filename)")
        } catch {
            AppLogger.log(tag: "ICloudFileStore", "Download request failed for \(filename): \(error)")
        }
    }

    // MARK: - Private Helpers

    private var legacyLocalBooksDirectory: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ).appendingPathComponent("Books", isDirectory: true)
    }

    private var legacyLocalCoversDirectory: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ).appendingPathComponent("Covers", isDirectory: true)
    }

    private func effectiveBooksDirectory() throws -> URL {
        if let dir = booksDirectory {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        return try makeLocalDirectory(named: "Books")
    }

    private func effectiveCoversDirectory() throws -> URL {
        if let dir = coversDirectory {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        return try makeLocalDirectory(named: "Covers")
    }

    private func makeLocalDirectory(named name: String) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createDirectoriesIfNeeded() {
        [booksDirectory, coversDirectory].forEach { url in
            guard let url else { return }
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
