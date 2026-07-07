import Foundation

/// Persists the reader's appearance settings.
///
/// The settings sheet saves on every control change — a slider drag produces
/// many saves per second — so saves update an in-memory cache and the disk
/// write plus sync notification are debounced. The lock guards cross-thread
/// access (main thread UI, SyncEngine actor on pull).
final class ReaderSettingsStore {
    static let shared = ReaderSettingsStore()

    /// Posted on the main queue after locally saved settings are flushed to
    /// disk (not posted for suppressed CloudKit pulls). Fires once per flush,
    /// not once per control tick.
    static let didSaveNotification = Notification.Name("ReaderSettingsStore.didSave")

    private static let saveDebounce: TimeInterval = 1.0

    private let saveURL: URL
    private let modifiedAtKey = "fathom.reader_settings.modifiedAt"
    private let ioQueue = DispatchQueue(label: "com.fathom.readersettings.io", qos: .utility)

    // All fields below are guarded by `lock`.
    private let lock = NSLock()
    private var cached: ReaderSettings?
    private var pendingSave: DispatchWorkItem?
    private var needsSyncNotification = false

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
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let loaded = (try? Data(contentsOf: saveURL))
            .flatMap { try? JSONDecoder().decode(ReaderSettings.self, from: $0) }
            ?? ReaderSettings()
        cached = loaded
        return loaded
    }

    /// - Parameter suppressSync: Pass `true` when applying a CloudKit pull so
    ///   the SyncEngine doesn't immediately push the settings back up.
    func save(_ settings: ReaderSettings, suppressSync: Bool = false) {
        lock.lock()
        cached = settings
        if !suppressSync { needsSyncNotification = true }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + Self.saveDebounce, execute: work)
        lock.unlock()

        UserDefaults.standard.set(Date(), forKey: modifiedAtKey)
    }

    /// Writes any pending save to disk immediately. Call when the app resigns
    /// active so a subsequent termination can't lose settings.
    func flush() {
        lock.lock()
        pendingSave?.cancel()
        pendingSave = nil
        lock.unlock()
        performSave()
    }

    /// The last time settings were written locally — used for CloudKit conflict resolution.
    var modifiedAt: Date? {
        UserDefaults.standard.object(forKey: modifiedAtKey) as? Date
    }

    private func performSave() {
        lock.lock()
        pendingSave = nil
        guard let settings = cached else {
            lock.unlock()
            return
        }
        let notify = needsSyncNotification
        needsSyncNotification = false
        lock.unlock()

        if let data = try? JSONEncoder().encode(settings) {
            do {
                try data.write(to: saveURL, options: .atomic)
            } catch {
                AppLogger.log(tag: "ReaderSettingsStore", "Failed to write settings: \(error)")
            }
        }

        guard notify else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didSaveNotification, object: nil)
        }
    }
}
