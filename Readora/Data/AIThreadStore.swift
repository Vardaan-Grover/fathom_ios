import Foundation

final class AIThreadStore {
    static let shared = AIThreadStore()
    private init() {}

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("ai_threads.json")
    }

    // Read
    func threads(forBookID bookID: UUID) -> [AIThread] {
        loadAll().filter{$0.bookID == bookID}
    }

    func thread(id: UUID) -> AIThread? {
        loadAll().first{$0.id == id}
    }

    // Write
    func createThread(_ thread: AIThread) {
        var all = loadAll()
        all.append(thread)
        saveAll(all)
    }

    func appendMessage(_ message: AIMessage, toThreadID threadID: UUID) {
        var all = loadAll()
        guard let index = all.firstIndex(where: {$0.id == threadID}) else { return }
        all[index].messages.append(message)
        saveAll(all)
    }

    func deleteThread(id: UUID) {
        var all = loadAll()
        all.removeAll{$0.id == id}
        saveAll(all)
    }

    // Private
    private func loadAll() -> [AIThread] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let threads = try? JSONDecoder().decode([AIThread].self, from: data)
        else { return [] }
        return threads
    }

    private func saveAll(_ threads: [AIThread]) {
        guard let data = try? JSONEncoder().encode(threads) else { return }

        try? data.write(to: fileURL, options: .atomic)
    }
}