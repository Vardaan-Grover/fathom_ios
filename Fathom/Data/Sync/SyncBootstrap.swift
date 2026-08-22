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
/// **This runs off the main actor deliberately.** It is called from `.task` on
/// a SwiftUI view, which is MainActor-isolated, so every non-async call in here
/// would otherwise run on the main thread — and the first one,
/// `ICloudFileStore.configure()`, resolves the ubiquity container, which is
/// documented as slow I/O and measured at ~870ms on a clean install.
///
/// `nonisolated` here is necessary but **not sufficient**, which cost a build
/// cycle to learn: `SWIFT_DEFAULT_ACTOR_ISOLATION` is MainActor, so calling
/// into a type that does not say otherwise hops straight back to the main
/// thread no matter how the caller is annotated. The stores this touches are
/// `nonisolated` for that reason, and `MainActorIsolationTests` keeps them
/// that way. The one step that genuinely needs the main actor asks for it
/// explicitly.
nonisolated enum SyncBootstrap {

    /// Idempotent: safe to call once per launch from the app root.
    static func start() async {
        let began = Date()
        func phase(_ name: String, _ since: Date) -> Date {
            let now = Date()
            AppLogger.log(tag: "SyncBootstrap",
                          "\(name) took \(Int(now.timeIntervalSince(since) * 1000))ms")
            return now
        }

        // 1. Resolve the iCloud container (no-op result if unavailable).
        ICloudFileStore.shared.configure()
        var mark = phase("container resolve", began)

        guard ICloudFileStore.shared.isAvailable else {
            // No entitlement, or the user is signed out of iCloud. Everything
            // falls back to local storage and the app works exactly as before.
            AppLogger.log(tag: "SyncBootstrap", "iCloud unavailable — running local-only")
            return
        }

        // 2. Start the iCloud download monitor. This one genuinely needs the
        //    main actor — it owns an NSMetadataQuery and publishes to SwiftUI.
        await MainActor.run {
            ICloudDownloadMonitor.shared.start()
        }
        mark = phase("monitor start", mark)

        // 3. Lift any pre-iCloud local files into the container.
        await LocalToICloudMigration.shared.migrateIfNeeded()
        mark = phase("file migration", mark)

        // 4. Start the CloudKit sync engine (push + pull).
        await SyncEngine.shared.start()
        _ = phase("engine start", mark)

        AppLogger.log(tag: "SyncBootstrap",
                      "iCloud sync started (\(Int(Date().timeIntervalSince(began) * 1000))ms total)")
    }
}
