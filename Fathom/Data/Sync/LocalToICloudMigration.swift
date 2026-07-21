import Foundation

/// Moves existing EPUBs and cover images from the legacy local directories
/// (ApplicationSupportDirectory/Books|Covers/) into the iCloud container
/// directories on first launch after sync is enabled.
///
/// - Migration is **idempotent**: files already at the destination are skipped.
/// - Migration is **per-device**: the completion flag records that this
///   device's local files have been lifted into the container. The container
///   is already private to the Apple ID, so there is no second identity to key
///   on (this flag used to be scoped by Supabase user ID).
/// - If iCloud is unavailable the migration silently skips; it will be retried
///   on the next launch when iCloud becomes available.
actor LocalToICloudMigration {

    static let shared = LocalToICloudMigration()
    private init() {}

    // MARK: - Entry Point

    /// Call after `ICloudFileStore.configure()` has returned.
    func migrateIfNeeded() async {
        guard ICloudFileStore.shared.isAvailable else {
            AppLogger.log(tag: "Migration", "Skipped — iCloud not available")
            return
        }

        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else {
            AppLogger.log(tag: "Migration", "Already migrated")
            return
        }

        AppLogger.log(tag: "Migration", "Starting file migration")

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

        UserDefaults.standard.set(true, forKey: Self.migrationKey)
        AppLogger.log(
            tag: "Migration",
            "Complete — \(migratedBooks) books, \(migratedCovers) covers moved to iCloud"
        )
    }

    // MARK: - Private

    /// v2: v1 keys were suffixed with the Supabase user ID. Bumping the version
    /// means a device that migrated under v1 re-runs once against the
    /// un-suffixed container paths — which is safe, since `migrate` skips files
    /// that already exist at the destination.
    private static let migrationKey = "fathom.icloud_file_migration_v2"

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
