import Foundation

/// Well-known file locations, resolved without crashing.
///
/// Several stores previously did `try! FileManager.url(for:
/// .applicationSupportDirectory, …, create: true)` in their initializers — an
/// I/O hiccup at launch (full disk, sandbox issue) became an instant crash.
/// This helper falls back through progressively less ideal directories
/// instead; the app degrades (state may not persist this run) but keeps
/// running.
enum AppFiles {
    /// Application Support, created if needed. Falls back to Caches, then the
    /// temporary directory, rather than crashing.
    static func applicationSupportDirectory() -> URL {
        let fm = FileManager.default
        if let url = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return url
        }
        AppLogger.log(tag: "AppFiles", "Application Support unavailable — falling back")
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return caches
        }
        return fm.temporaryDirectory
    }
}
