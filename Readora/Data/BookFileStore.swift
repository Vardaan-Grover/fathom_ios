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
}
