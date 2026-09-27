import Foundation
import ImageIO
import UIKit

/// Thin compatibility shim — all real work is delegated to `ICloudFileStore`.
///
/// Existing call sites continue to compile unchanged while transparently writing
/// to and reading from the iCloud container (with a local fallback when iCloud
/// is unavailable).
///
/// **Deliberately `nonisolated`.** `SWIFT_DEFAULT_ACTOR_ISOLATION` is MainActor,
/// so an unannotated enum is a main-actor enum, and `coverImage(for:)` blocks in
/// `pread` while iCloud materialises the file. Every caller that wrapped this in
/// `Task.detached` to stay off the main thread was hopping right back onto it —
/// the detached task starts off main and then the first call into this type
/// returns it there. See `DetachedIsolationProbe` for the demonstration.
nonisolated enum BookFileStore {

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

    /// Deletes a book's files — the EPUB, its cover and its reflection image —
    /// everywhere they are stored. Call after the database row is gone.
    static func deleteFiles(bookFilename: String?, coverFilename: String?, reflectionFilename: String?) {
        ICloudFileStore.shared.deleteFiles(bookFilename: bookFilename,
                                           coverFilename: coverFilename,
                                           reflectionFilename: reflectionFilename)
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
    /// `nonisolated(unsafe)` because NSCache does its own locking — it is
    /// documented as safe to use from multiple threads — but is not marked
    /// Sendable, so the compiler cannot see that.
    nonisolated(unsafe) private static let coverImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Covers are stored at whatever resolution the EPUB shipped (often
    /// 1600×2400+, ~15 MB decoded), but the largest on-screen cover is a
    /// library-grid tile ~285 pt tall (~855 px @3x). Decoding through this
    /// ceiling keeps each cached cover ~2 MB instead of ~15 MB.
    private static let coverMaxPixelDimension: CGFloat = 900

    /// Loads and caches the cover image for the given filename, downsampled
    /// to the largest size any view actually displays.
    static func coverImage(for filename: String?) -> UIImage? {
        guard let filename else { return nil }
        let key = filename as NSString
        if let cached = coverImageCache.object(forKey: key) {
            return cached
        }
        guard let url = coverURL(for: filename),
            let image = downsampledImage(at: url, maxPixelDimension: coverMaxPixelDimension)
        else { return nil }
        let cost: Int
        if let cgImage = image.cgImage {
            cost = cgImage.bytesPerRow * cgImage.height
        } else {
            cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        }
        coverImageCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Decodes an image at a bounded pixel size without ever materializing the
    /// full-resolution bitmap (ImageIO downsamples during decode).
    private static func downsampledImage(at url: URL, maxPixelDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
