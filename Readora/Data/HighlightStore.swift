import Foundation

final class HighlightStore {
    static let shared = HighlightStore()

    private init() {}

    private var fileURL: URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return appSupport.appendingPathComponent("highlights.json")
    }

    func save(_ highlights: [Highlight]) {
        guard let data = try? JSONEncoder().encode(highlights) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func load() -> [Highlight] {
        guard let data = try? Data(contentsOf: fileURL),
            let highlights = try? JSONDecoder().decode([Highlight].self, from: data)
        else { return [] }

        return highlights
    }

    func highlights(forBookID bookID: UUID) -> [Highlight] {
        load().filter {$0.bookID == bookID}
    }

    func add(_ highlight: Highlight) {
        var all = load()
        all.append(highlight)
        save(all)
    }

    func delete(id: UUID) {
        var all = load()
        all.removeAll {$0.id == id}
        save(all)
    }

    func updateColor(id: UUID, color: HighlightColor) {
        var all = load()
        if let index = all.firstIndex(where: {$0.id == id}) {
            all[index].color = color
        }
        save(all)
    }
}
