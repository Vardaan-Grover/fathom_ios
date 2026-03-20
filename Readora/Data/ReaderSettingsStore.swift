import Foundation

final class ReaderSettingsStore {
    static let shared = ReaderSettingsStore()

    private let saveURL: URL

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
        let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data) else {return ReaderSettings()}

        return decoded
    }

    func save(_ settings: ReaderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {return}
        try? data.write(to: saveURL, options: .atomic)
    }
}