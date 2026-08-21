import Foundation
import ReadiumShared

/// Everything known about where the reader is in a book.
///
/// `position` and `furthestProgression` answer different questions and are
/// resolved independently when a remote copy arrives: the first is "where was I
/// last", which the most recent write wins; the second is "how far did I ever
/// get", which only moves forward. Keeping both is what lets a device that has
/// fallen behind offer to jump forward instead of silently dragging the reader
/// backwards. See §3.6 of docs/sync-conflict-policy.md.
struct ReadingState: Codable, Equatable {
    /// Readium locator JSON for the last position.
    var locatorJSON: String
    /// When this device last wrote `locatorJSON`.
    var savedAt: Date
    /// High-water mark of `locations.totalProgression`, 0...1. Never decreases.
    var furthestProgression: Double
}

/// Persists reading state (Readium locator, save time, furthest progress) per
/// book.
///
/// Positions change on every page turn, so this store is built to make saves
/// cheap: all reads and writes go through an in-memory cache guarded by a
/// lock (it is hit from the main thread and from the SyncEngine actor), and
/// the backing JSON file is rewritten on a background queue, debounced.
/// `flush()` forces the pending write out — call it when the app leaves the
/// foreground so a force-quit can't lose more than the debounce window.
///
/// All three fields live in the same file. `savedAt` used to sit in
/// UserDefaults while the locator sat here, which meant a crash between the two
/// writes left a position stamped with the wrong time — and that timestamp is
/// what decided sync conflicts. One atomically-replaced file either has the new
/// state or the old one.
final class ReadingStateStore {
    static let shared = ReadingStateStore()

    /// Posted on the main queue after locally saved positions are flushed to
    /// disk (not posted for suppressed CloudKit pulls). Fires once per flush,
    /// not once per page turn. `userInfo["bookID"]` is the affected `UUID`.
    static let didSaveNotification = Notification.Name("ReadingStateStore.didSave")

    private static let writeDebounce: TimeInterval = 2.0

    private let saveURL: URL
    private let ioQueue = DispatchQueue(label: "com.fathom.readingstate.io", qos: .utility)

    // All fields below are guarded by `lock`.
    private let lock = NSLock()
    private var cache: [String: ReadingState]?    // bookID.uuidString → state
    private var isDirty = false                   // cache differs from disk
    private var booksAwaitingSyncNotification: Set<UUID> = []
    private var pendingWrite: DispatchWorkItem?

    private init() {
        saveURL = AppFiles.applicationSupportDirectory()
            .appendingPathComponent("reading_state.json")
    }

    /// Test seam: an instance backed by its own file, so tests exercise the
    /// real merge and persistence paths without sharing the app's state.
    init(saveURLForTesting url: URL) {
        saveURL = url
    }

    // MARK: - Locator read/write

    /// Saves the locator for a book. Cheap: updates the in-memory cache and
    /// schedules a debounced background disk write.
    /// - Parameter suppressSync: Pass `true` when applying a CloudKit pull so
    ///   the SyncEngine doesn't immediately push it back up.
    func saveLocator(_ locator: Locator, forBookID bookID: UUID, suppressSync: Bool = false) {
        guard let jsonString = locator.jsonString else { return }
        let progression = locator.locations.totalProgression ?? 0

        lock.lock()
        loadCacheIfNeededLocked()
        let key = bookID.uuidString
        let previousFurthest = cache?[key]?.furthestProgression ?? 0
        cache?[key] = ReadingState(
            locatorJSON: jsonString,
            savedAt: Date(),
            // Reading backwards, re-reading, or jumping to a bookmark must not
            // pull the high-water mark down with it.
            furthestProgression: max(previousFurthest, progression)
        )
        isDirty = true
        if !suppressSync { booksAwaitingSyncNotification.insert(bookID) }
        scheduleWriteLocked()
        lock.unlock()
    }

    func loadLocator(forBookID bookID: UUID) -> Locator? {
        guard let jsonString = locatorJSON(forBookID: bookID) else { return nil }
        return try? Locator(jsonString: jsonString)
    }

    func locatorJSON(forBookID bookID: UUID) -> String? {
        state(forBookID: bookID)?.locatorJSON
    }

    func state(forBookID bookID: UUID) -> ReadingState? {
        lock.lock()
        defer { lock.unlock() }
        loadCacheIfNeededLocked()
        return cache?[bookID.uuidString]
    }

    /// Writes any pending changes to disk immediately. Call when the app
    /// resigns active so a subsequent termination can't lose positions.
    func flush() {
        lock.lock()
        pendingWrite?.cancel()
        pendingWrite = nil
        lock.unlock()
        performWrite()
    }

    // MARK: - Sync accessors

    func savedAt(forBookID bookID: UUID) -> Date? {
        state(forBookID: bookID)?.savedAt
    }

    /// How far the reader has ever got in this book, 0...1.
    func furthestProgression(forBookID bookID: UUID) -> Double {
        state(forBookID: bookID)?.furthestProgression ?? 0
    }

    /// Applies a copy of this book's reading state that arrived from another
    /// device.
    ///
    /// The two halves resolve independently and deliberately. The position is
    /// last-write-wins, so an older remote position is ignored. The furthest
    /// progression is a high-water mark, so it is taken whenever it is larger —
    /// *including* when the position it arrived with lost. A device that read
    /// ahead and then had its position superseded still contributed the fact
    /// that the reader got that far.
    ///
    /// - Returns: `true` if the current position was replaced.
    @discardableResult
    func applyRemoteState(locatorJSON: String,
                          savedAt: Date,
                          furthestProgression: Double,
                          forBookID bookID: UUID) -> Bool {
        lock.lock()
        loadCacheIfNeededLocked()
        let key = bookID.uuidString
        let existing = cache?[key]

        let takePosition = existing.map { savedAt > $0.savedAt } ?? true
        let mergedFurthest = max(existing?.furthestProgression ?? 0, furthestProgression)

        if takePosition {
            cache?[key] = ReadingState(locatorJSON: locatorJSON,
                                       savedAt: savedAt,
                                       furthestProgression: mergedFurthest)
            isDirty = true
        } else if mergedFurthest > (existing?.furthestProgression ?? 0), var kept = existing {
            kept.furthestProgression = mergedFurthest
            cache?[key] = kept
            isDirty = true
        }

        let changed = isDirty
        if changed { scheduleWriteLocked() }
        lock.unlock()

        // Deliberately not added to booksAwaitingSyncNotification: this state
        // came from the sync engine, and echoing it back would push a record we
        // just received.
        return takePosition
    }

    // MARK: - Private

    /// Must be called with `lock` held.
    private func loadCacheIfNeededLocked() {
        guard cache == nil else { return }

        guard let data = try? Data(contentsOf: saveURL) else {
            cache = [:]
            return
        }

        if let decoded = try? JSONDecoder().decode([String: ReadingState].self, from: data) {
            cache = decoded
            return
        }

        // Legacy format: bookID → locator JSON, with savedAt in UserDefaults
        // and no furthest-progression record at all. Upgrade in place; the
        // high-water mark starts from wherever the stored position is, which is
        // the best available estimate of how far the reader got.
        if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
            var upgraded: [String: ReadingState] = [:]
            for (key, locatorJSON) in legacy {
                let progression = (try? Locator(jsonString: locatorJSON))?
                    .locations.totalProgression ?? 0
                let savedAt = UUID(uuidString: key)
                    .flatMap { UserDefaults.standard.object(forKey: legacySavedAtKey(for: $0)) as? Date }
                upgraded[key] = ReadingState(locatorJSON: locatorJSON,
                                             savedAt: savedAt ?? .distantPast,
                                             furthestProgression: progression)
            }
            cache = upgraded
            isDirty = true   // persist the upgraded shape on the next write
            AppLogger.log(tag: "ReadingStateStore",
                          "Upgraded \(upgraded.count) legacy reading-state entries")
            return
        }

        AppLogger.log(tag: "ReadingStateStore", "Unreadable reading state — starting empty")
        cache = [:]
    }

    /// Must be called with `lock` held.
    private func scheduleWriteLocked() {
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performWrite() }
        pendingWrite = work
        ioQueue.asyncAfter(deadline: .now() + Self.writeDebounce, execute: work)
    }

    private func performWrite() {
        lock.lock()
        pendingWrite = nil
        guard isDirty, let snapshot = cache else {
            lock.unlock()
            return
        }
        isDirty = false
        let toNotify = booksAwaitingSyncNotification
        booksAwaitingSyncNotification = []
        lock.unlock()

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: saveURL, options: .atomic)
        } catch {
            AppLogger.log(tag: "ReadingStateStore", "Failed to write reading state: \(error)")
        }

        guard !toNotify.isEmpty else { return }
        DispatchQueue.main.async {
            for bookID in toNotify {
                NotificationCenter.default.post(
                    name: Self.didSaveNotification,
                    object: nil,
                    userInfo: ["bookID": bookID]
                )
            }
        }
    }

    private func legacySavedAtKey(for bookID: UUID) -> String {
        "fathom.reading_state.savedAt.\(bookID.uuidString)"
    }
}
