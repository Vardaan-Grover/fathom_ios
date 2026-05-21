import Foundation
import ReadiumShared

final class ReadingStateStore {
    static let shared = ReadingStateStore()

    /// Posted on the main queue after any local save (not suppressed CloudKit pulls).
    /// `userInfo["bookID"]` is the affected `UUID`.
    static let didSaveNotification = Notification.Name("ReadingStateStore.didSave")

    private let saveURL: URL

    private init() {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        saveURL = appSupport.appendingPathComponent("reading_state.json")
    }

    // MARK: - Locator read/write

    private func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveAll(_ state: [String: String]) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    /// Saves the locator for a book.
    /// - Parameter suppressSync: Pass `true` when applying a CloudKit pull so
    ///   the SyncEngine doesn't immediately push it back up.
    func saveLocator(_ locator: Locator, forBookID bookID: UUID, suppressSync: Bool = false) {
        guard let jsonString = locator.jsonString else { return }
        var state = loadAll()
        state[bookID.uuidString] = jsonString
        saveAll(state)

        // Stamp the save time for CloudKit conflict resolution.
        UserDefaults.standard.set(Date(), forKey: savedAtKey(for: bookID))

        if !suppressSync {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.didSaveNotification,
                    object: nil,
                    userInfo: ["bookID": bookID]
                )
            }
        }
    }

    func loadLocator(forBookID bookID: UUID) -> Locator? {
        guard let jsonString = loadAll()[bookID.uuidString] else { return nil }
        return try? Locator(jsonString: jsonString)
    }

    // MARK: - Timestamp (for CloudKit conflict resolution)

    func savedAt(forBookID bookID: UUID) -> Date? {
        UserDefaults.standard.object(forKey: savedAtKey(for: bookID)) as? Date
    }

    func locatorJSON(forBookID bookID: UUID) -> String? {
        loadAll()[bookID.uuidString]
    }

    private func savedAtKey(for bookID: UUID) -> String {
        "fathom.reading_state.savedAt.\(bookID.uuidString)"
    }
}