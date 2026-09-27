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

    /// Posted on the main queue when settings change from *another device*, so
    /// an open reader can pick them up instead of later saving its stale copy
    /// over them.
    static let didChangeRemotelyNotification = Notification.Name("ReaderSettingsStore.didChangeRemotely")

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
        saveURL = AppFiles.applicationSupportDirectory()
            .appendingPathComponent("reader_settings.json")
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

    /// Saves a change the reader made on this device.
    func save(_ settings: ReaderSettings) {
        lock.lock()
        cached = settings
        needsSyncNotification = true
        scheduleSaveLocked()
        lock.unlock()

        UserDefaults.standard.set(Date(), forKey: modifiedAtKey)
    }

    /// Adopts settings that arrived from another device.
    ///
    /// `modifiedAt` is the *remote* edit time, not now. Stamping the time of
    /// the apply made this device claim a later edit than it had made: it then
    /// rejected genuinely newer changes from a third device and drifted away
    /// from what iCloud held.
    ///
    /// Any local change still waiting for its debounced sync notification is
    /// superseded — the caller only gets here when the remote copy is newer —
    /// so the pending push is cancelled rather than sending these remote
    /// settings back up as if they were local.
    func applyRemote(_ settings: ReaderSettings, modifiedAt: Date) {
        lock.lock()
        cached = settings
        needsSyncNotification = false
        scheduleSaveLocked()
        lock.unlock()

        UserDefaults.standard.set(modifiedAt, forKey: modifiedAtKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeRemotelyNotification, object: nil)
        }
    }

    /// Writes any pending save to disk immediately. Call when the app resigns
    /// active so a subsequent termination can't lose settings.
    ///
    /// - Returns: whether a local change had not yet been announced to sync.
    @discardableResult
    func flush() -> Bool {
        lock.lock()
        pendingSave?.cancel()
        pendingSave = nil
        lock.unlock()
        return performSave()
    }

    /// Must be called with `lock` held.
    private func scheduleSaveLocked() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + Self.saveDebounce, execute: work)
    }

    /// The last time settings were written locally — used for CloudKit conflict resolution.
    var modifiedAt: Date? {
        UserDefaults.standard.object(forKey: modifiedAtKey) as? Date
    }

    @discardableResult
    private func performSave() -> Bool {
        lock.lock()
        pendingSave = nil
        guard let settings = cached else {
            lock.unlock()
            return false
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

        guard notify else { return false }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didSaveNotification, object: nil)
        }
        return true
    }
}
