import Foundation

enum BookFileStore {
    static func copyIntoAppLibrary(from incomingURL: URL) throws -> URL {
        let fm = FileManager.default

        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let booksDir = appSupport.appendingPathComponent("Books", isDirectory: true)
        if !fm.fileExists(atPath: booksDir.path) {
            try fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        }

        let baseName = incomingURL.deletingPathExtension().lastPathComponent
        let ext = incomingURL.pathExtension
        let uniqueName = "\(baseName)-\(UUID().uuidString).\(ext)"
        let destURL = booksDir.appendingPathComponent(uniqueName)
        try fm.copyItem(at: incomingURL, to: destURL)
        return destURL
    }

    static func saveCoverImage(_ data: Data, coverID: UUID) throws -> String {
        let fm = FileManager.default

        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let coversDir = appSupport.appendingPathComponent("Covers", isDirectory: true)
        if !fm.fileExists(atPath: coversDir.path) {
            try fm.createDirectory(at: coversDir, withIntermediateDirectories: true)
        }

        let filename = "\(coverID.uuidString).png"
        let destURL = coversDir.appendingPathComponent(filename)
        try data.write(to: destURL, options: .atomic)
        return filename
    }

    static func coverURL(for filename: String) -> URL? {
        guard
            let appSupport = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: false)
        else { return nil }
        return appSupport.appendingPathComponent("Covers").appendingPathComponent(filename)
    }
}
