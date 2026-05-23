import Foundation

/// Thin compatibility shim — all real work is delegated to `ICloudFileStore`.
///
/// Existing call sites continue to compile unchanged while transparently writing
/// to and reading from the iCloud container (with a local fallback when iCloud
/// is unavailable).
enum BookFileStore {

    /// Copies an EPUB into the managed store and returns its destination URL.
    /// `url.lastPathComponent` of the returned URL is what you store as
    /// `Book.localFilename`.
    @discardableResult
    static func copyIntoAppLibrary(from incomingURL: URL) throws -> URL {
        try ICloudFileStore.shared.copyBook(from: incomingURL)
    }

    /// Saves cover PNG data and returns the filename to store as
    /// `Book.coverFilename`.
    static func saveCoverImage(_ data: Data, coverID: UUID) throws -> String {
        try ICloudFileStore.shared.saveCover(data, coverID: coverID)
    }

    /// Resolves the full URL for a cover image filename.
    static func coverURL(for filename: String) -> URL? {
        ICloudFileStore.shared.coverURL(for: filename)
    }

    /// Saves reflection image PNG data and returns the filename to store as
    /// `Book.reflectionImageFilename`.
    static func saveReflectionImage(_ data: Data, imageID: UUID = UUID()) throws -> String {
        try ICloudFileStore.shared.saveReflectionImage(data, imageID: imageID)
    }

    /// Resolves the full URL for a reflection image filename.
    static func reflectionImageURL(for filename: String) -> URL? {
        ICloudFileStore.shared.reflectionImageURL(for: filename)
    }
}
