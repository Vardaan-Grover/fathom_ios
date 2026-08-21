import CloudKit
import Foundation

/// Persists `CKSyncEngine`'s state between launches.
///
/// The serialization holds the server change tokens *and* the set of local
/// changes that have not yet been confirmed as sent. Losing it is not fatal —
/// the engine re-fetches from scratch — but losing it silently and often means
/// every launch re-downloads the whole zone, so it is worth storing carefully.
///
/// This deliberately does not use `UserDefaults`. The previous engine kept its
/// change tokens there, which made sync state a set of loose keys that could be
/// half-written relative to the database rows they described. A single file,
/// replaced atomically, at least fails as a unit: either the new state is
/// there or the old one is.
///
/// The file lives in Application Support, which is local to the device and
/// excluded from iCloud. Sync state is per-device by definition — syncing it
/// would be a category error.
nonisolated enum SyncStateStore {

    private static let filename = "cksyncengine-state.json"

    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true) else {
            AppLogger.log(tag: "SyncStateStore", "No Application Support directory")
            return nil
        }
        return dir.appendingPathComponent(filename)
    }

    // MARK: - Load

    static func load() -> CKSyncEngine.State.Serialization? {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            // A corrupt or version-incompatible state file must not wedge the
            // app. Dropping it costs one full re-fetch and recovers cleanly.
            AppLogger.log(tag: "SyncStateStore", "Discarding unreadable state: \(error)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    // MARK: - Save

    static func save(_ state: CKSyncEngine.State.Serialization) {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(state)
            // .atomic replaces via a temporary file, so a crash mid-write
            // leaves the previous state intact rather than a truncated file.
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.log(tag: "SyncStateStore", "Failed to persist state: \(error)")
        }
    }

    // MARK: - Reset

    /// Clears persisted state. Called when the iCloud account changes — the
    /// tokens and pending changes belong to the previous account's zone and are
    /// meaningless (and misleading) against a different one.
    static func reset() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        AppLogger.log(tag: "SyncStateStore", "State reset")
    }
}
