import Foundation

/// Moves existing EPUBs and cover images from the legacy local directories
/// (ApplicationSupportDirectory/Books|Covers/) into the user-scoped iCloud
/// container directories on first launch after sync is enabled.
///
/// - Migration is **idempotent**: files already at the destination are skipped.
/// - Migration is **per-user**: the completion flag is keyed to the Supabase
///   user ID so a different account on the same device migrates its own files.
/// - If iCloud is unavailable the migration silently skips; it will be retried
///   on the next launch when iCloud becomes available.
actor LocalToICloudMigration {

    static let shared = LocalToICloudMigration()
    private init() {}

    // MARK: - Entry Point

    /// Call after `ICloudFileStore.configure(userID:)` has returned.
    func migrateIfNeeded() async {
        guard ICloudFileStore.shared.isAvailable,
              let userID = ICloudFileStore.shared.userID
        else {
            AppLogger.log(tag: "Migration", "Skipped — iCloud not available")
            return
        }

        let key = migrationKey(for: userID)
        guard !UserDefaults.standard.bool(forKey: key) else {
            AppLogger.log(tag: "Migration", "Already migrated for user \(userID)")
            return
        }

        AppLogger.log(tag: "Migration", "Starting file migration for user \(userID)")

        let fm = FileManager.default
        guard
            let appSupport = try? fm.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            )
        else { return }

        let localBooks  = appSupport.appendingPathComponent("Books",  isDirectory: true)
        let localCovers = appSupport.appendingPathComponent("Covers", isDirectory: true)

        var migratedBooks  = 0
        var migratedCovers = 0

        if let targetDir = ICloudFileStore.shared.booksDirectory {
            migratedBooks = migrate(from: localBooks, to: targetDir, using: fm)
        }

        if let targetDir = ICloudFileStore.shared.coversDirectory {
            migratedCovers = migrate(from: localCovers, to: targetDir, using: fm)
        }

        UserDefaults.standard.set(true, forKey: key)
        AppLogger.log(
            tag: "Migration",
            "Complete — \(migratedBooks) books, \(migratedCovers) covers moved to iCloud"
        )
    }

    // MARK: - Private

    private func migrationKey(for userID: UUID) -> String {
        "fathom.icloud_file_migration_v1.\(userID.uuidString)"
    }

    /// Moves every file in `source` to `destination`, creating `destination` if
    /// needed.  Files that already exist at the destination are skipped.
    /// Returns the number of files actually moved.
    @discardableResult
    private func migrate(from source: URL, to destination: URL, using fm: FileManager) -> Int {
        guard fm.fileExists(atPath: source.path) else { return 0 }

        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            AppLogger.log(tag: "Migration", "Failed to create destination \(destination.lastPathComponent): \(error)")
            return 0
        }

        guard let files = try? fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        var count = 0
        for file in files {
            let dest = destination.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                // Already migrated (or placed there by another device via iCloud).
                continue
            }
            do {
                try fm.moveItem(at: file, to: dest)
                count += 1
            } catch {
                AppLogger.log(tag: "Migration", "Could not move \(file.lastPathComponent): \(error)")
            }
        }
        return count
    }
}
