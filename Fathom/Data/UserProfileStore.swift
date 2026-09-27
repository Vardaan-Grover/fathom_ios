import Foundation

// MARK: - UserProfile

struct UserProfile: Codable, Equatable {
    var displayName: String?
    var avatarEmoji: String?
    var avatarColorHex: String

    static let `default` = UserProfile(
        displayName: nil,
        avatarEmoji: nil,
        avatarColorHex: "5B7CB0"
    )
}

// MARK: - UserProfileStore
//
// Local-first profile storage backed by a JSON file in Application Support.
// Mirrors the ReaderSettingsStore pattern: any save posts
// `didSaveNotification` which SyncEngine listens for to push to CloudKit.

final class UserProfileStore {
    static let shared = UserProfileStore()

    /// Posted on the main queue after any local save (suppressed when applying a CloudKit pull).
    static let didSaveNotification = Notification.Name("UserProfileStore.didSave")

    /// Posted on the main queue after any change (local save OR CloudKit pull).
    /// UI should observe this to refresh.
    static let didChangeNotification = Notification.Name("UserProfileStore.didChange")

    private let saveURL: URL
    private let modifiedAtKey = "fathom.user_profile.modifiedAt"

    private init() {
        saveURL = AppFiles.applicationSupportDirectory()
            .appendingPathComponent("user_profile.json")
    }

    // MARK: - Load / Save

    func load() -> UserProfile {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return .default }
        return decoded
    }

    /// Saves a change made on this device.
    func save(_ profile: UserProfile) {
        write(profile, modifiedAt: Date(), suppressSync: false)
    }

    /// Adopts a profile that arrived from another device, keeping that
    /// device's edit time rather than stamping now — see
    /// `ReaderSettingsStore.applyRemote` for why that matters.
    func applyRemote(_ profile: UserProfile, modifiedAt: Date) {
        write(profile, modifiedAt: modifiedAt, suppressSync: true)
    }

    private func write(_ profile: UserProfile, modifiedAt: Date, suppressSync: Bool) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        do {
            try data.write(to: saveURL, options: .atomic)
        } catch {
            AppLogger.log(tag: "UserProfileStore", "Failed to write profile: \(error)")
        }

        UserDefaults.standard.set(modifiedAt, forKey: modifiedAtKey)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            if !suppressSync {
                NotificationCenter.default.post(name: Self.didSaveNotification, object: nil)
            }
        }
    }

    var modifiedAt: Date? {
        UserDefaults.standard.object(forKey: modifiedAtKey) as? Date
    }
}
