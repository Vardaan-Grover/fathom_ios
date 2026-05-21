import Foundation

final class ReaderSettingsStore {
    static let shared = ReaderSettingsStore()

    /// Posted on the main queue after any local save (not suppressed CloudKit pulls).
    static let didSaveNotification = Notification.Name("ReaderSettingsStore.didSave")

    private let saveURL: URL
    private let modifiedAtKey = "fathom.reader_settings.modifiedAt"

    private init() {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        saveURL = appSupport.appendingPathComponent("reader_settings.json")
    }

    func load() -> ReaderSettings {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data)
        else { return ReaderSettings() }
        return decoded
    }

    /// - Parameter suppressSync: Pass `true` when applying a CloudKit pull so
    ///   the SyncEngine doesn't immediately push the settings back up.
    func save(_ settings: ReaderSettings, suppressSync: Bool = false) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: saveURL, options: .atomic)

        UserDefaults.standard.set(Date(), forKey: modifiedAtKey)

        if !suppressSync {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didSaveNotification, object: nil)
            }
        }
    }

    /// The last time settings were written locally — used for CloudKit conflict resolution.
    var modifiedAt: Date? {
        UserDefaults.standard.object(forKey: modifiedAtKey) as? Date
    }
}