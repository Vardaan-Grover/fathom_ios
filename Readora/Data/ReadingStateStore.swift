import Foundation
import ReadiumShared

final class ReadingStateStore {
    static let shared = ReadingStateStore()

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

    private func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: saveURL),
        let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {return [:]}

        return decoded
    }

    private func saveAll(_ state: [String: String]) {
        guard let data = try? JSONEncoder().encode(state) else {return}
        try? data.write(to: saveURL, options: .atomic)
    }

    func saveLocator(_ locator: Locator, forBookID bookID: UUID) {
        guard let jsonString = locator.jsonString else {return}
        var state = loadAll()
        state[bookID.uuidString] = jsonString
        saveAll(state)
    }

    func loadLocator(forBookID bookID: UUID) -> Locator? {
        guard let jsonString = loadAll()[bookID.uuidString] else {return nil}

        return try? Locator(jsonString: jsonString)
    }
}