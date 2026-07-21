import Foundation

/// Brings iCloud storage and CloudKit sync up at launch.
///
/// This sequence used to hang off Supabase sign-in, which coupled sync to a
/// Fathom account it never actually needed: the ubiquity container and the
/// private CloudKit database are both scoped by Apple ID, not by anything the
/// app supplies. Sync now starts once at launch and is gated only on whether
/// iCloud itself is available.
///
/// Ordering matters — the file store must resolve the container before the
/// migrator or the download monitor touch any path.
enum SyncBootstrap {

    /// Idempotent: safe to call once per launch from the app root.
    static func start() async {
        // 1. Resolve the iCloud container (no-op result if unavailable).
        ICloudFileStore.shared.configure()

        guard ICloudFileStore.shared.isAvailable else {
            // No entitlement, or the user is signed out of iCloud. Everything
            // falls back to local storage and the app works exactly as before.
            AppLogger.log(tag: "SyncBootstrap", "iCloud unavailable — running local-only")
            return
        }

        // 2. Start the iCloud download monitor on the main actor.
        await MainActor.run {
            ICloudDownloadMonitor.shared.start()
        }

        // 3. Lift any pre-iCloud local files into the container.
        await LocalToICloudMigration.shared.migrateIfNeeded()

        // 4. Start the CloudKit sync engine (push + pull).
        await SyncEngine.shared.start()

        AppLogger.log(tag: "SyncBootstrap", "iCloud sync started")
    }
}
