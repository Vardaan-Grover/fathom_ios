import Foundation
import UIKit

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

    /// In-memory cache of decoded cover images, keyed by cover filename.
    /// Cover art is read from disk frequently (shelf rows, recently-read tile,
    /// reorder sheets, etc.); caching the decoded image avoids re-reading and
    /// re-decoding from disk on every view re-render, which is a major source
    /// of scroll jank.
    private static let coverImageCache = NSCache<NSString, UIImage>()

    /// Loads and caches the cover image for the given filename.
    static func coverImage(for filename: String?) -> UIImage? {
        guard let filename else { return nil }
        let key = filename as NSString
        if let cached = coverImageCache.object(forKey: key) {
            return cached
        }
        guard let url = coverURL(for: filename), let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        coverImageCache.setObject(image, forKey: key)
        return image
    }
}
