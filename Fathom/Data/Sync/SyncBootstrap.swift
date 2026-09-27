import Foundation

/// Brings iCloud storage and CloudKit sync up at launch.
///
/// Two independent services, gated independently:
///
/// - **CloudKit** (records) starts unconditionally. `CKSyncEngine` waits by
///   itself for an iCloud account and reports account changes as events, so
///   there is nothing to check first. It used to start only when the iCloud
///   *Drive* container resolved, which meant a reader with iCloud Drive turned
///   off for Fathom got no sync at all — not even highlights — although
///   CloudKit would have worked.
/// - **iCloud Drive** (book files) needs the ubiquity container, which exists
///   only when the reader is signed in with iCloud Drive enabled.
///
/// Called from `FathomApp.init`, not from a view: Apple's guidance is to create
/// the sync engine as soon as the process launches, because that is when it
/// starts listening for pushes. A silent push can launch the app in the
/// background without any scene — and so without any view `.task` — running.
///
/// **This runs off the main actor deliberately.** Resolving the ubiquity
/// container is slow I/O (measured at ~870ms on a clean install).
/// `SWIFT_DEFAULT_ACTOR_ISOLATION` is MainActor, so every type touched here is
/// explicitly `nonisolated`, and `MainActorIsolationTests` keeps them that way.
nonisolated enum SyncBootstrap {

    private static let once = OnceFlag()

    /// Idempotent: the second and later calls return immediately.
    static func start() async {
        guard once.claim() else { return }

        let began = Date()
        func phase(_ name: String, _ since: Date) -> Date {
            let now = Date()
            AppLogger.log(tag: "SyncBootstrap",
                          "\(name) took \(Int(now.timeIntervalSince(since) * 1000))ms")
            return now
        }

        // 1. Records. Needs nothing from the file side.
        await SyncEngine.shared.start()
        var mark = phase("engine start", began)

        // 2. Files. Resolves the container (nil when iCloud Drive is off).
        ICloudFileStore.shared.configure()
        mark = phase("container resolve", mark)

        // 3. Follow the iCloud identity for the rest of the process: signing
        //    in, out, or into a different Apple ID changes the container.
        ICloudIdentityObserver.start()

        if ICloudFileStore.shared.isAvailable {
            // The download monitor owns an NSMetadataQuery and publishes to
            // SwiftUI, so it genuinely needs the main actor.
            await MainActor.run {
                ICloudDownloadMonitor.shared.start()
            }
            mark = phase("monitor start", mark)

            await LocalToICloudMigration.shared.migrateIfNeeded()
            _ = phase("file migration", mark)
        } else {
            AppLogger.log(tag: "SyncBootstrap", "iCloud Drive unavailable — book files stay local")
        }

        AppLogger.log(tag: "SyncBootstrap",
                      "iCloud sync started (\(Int(Date().timeIntervalSince(began) * 1000))ms total)")
    }
}

/// Re-resolves the iCloud Drive container when the signed-in identity
/// changes. Without this a sign-in, sign-out or account switch while the app
/// was running left the file store pointing at a container that was no longer
/// there (or never looking at one that now was) until the next launch.
nonisolated enum ICloudIdentityObserver {

    private static let once = OnceFlag()

    static func start() {
        guard once.claim() else { return }
        _ = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: nil
        ) { _ in
            Task.detached(priority: .utility) {
                AppLogger.log(tag: "ICloudIdentity", "iCloud identity changed — re-resolving container")
                ICloudFileStore.shared.configure()
                let available = ICloudFileStore.shared.isAvailable
                await MainActor.run {
                    ICloudDownloadMonitor.shared.stop()
                    if available { ICloudDownloadMonitor.shared.start() }
                }
                if available {
                    await LocalToICloudMigration.shared.migrateIfNeeded()
                }
            }
        }
    }
}

/// A thread-safe "has this run yet" latch.
nonisolated final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True exactly once — for the first caller.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
