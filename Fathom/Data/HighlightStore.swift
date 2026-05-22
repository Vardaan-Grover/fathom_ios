import Foundation
import GRDB

final class HighlightStore {
    static let shared = HighlightStore()

    static let didChangeNotification = Notification.Name("HighlightStore.didChange")

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    private init() {
        migrateFromJSONIfNeeded()
    }

    func add(_ highlight: Highlight) {
        do {
            try dbQueue.write { db in
                try highlight.insert(db)
            }
            notifyChange(bookID: highlight.bookID)
        } catch {
            AppLogger.log(tag: "HighlightStore", "Error adding highlight: \(error)")
        }
    }

    func delete(id: UUID) {
        var bookID: UUID?
        do {
            try dbQueue.write { db in
                if var highlight = try Highlight.fetchOne(db, id: id) {
                    bookID = highlight.bookID
                    highlight.deletedAt = Date()
                    try highlight.update(db)
                }
            }
            if let bookID { notifyChange(bookID: bookID) }
        } catch {
            AppLogger.log(tag: "HighlightStore", "Error soft-deleting highlight: \(error)")
        }
    }

    func updateColor(id: UUID, color: HighlightColor) {
        var affectedBookID: UUID?
        do {
            try dbQueue.write { db in
                if var highlight = try Highlight.fetchOne(db, id: id) {
                    highlight.color = color
                    try highlight.update(db)
                    affectedBookID = highlight.bookID
                }
            }
            if let bookID = affectedBookID { notifyChange(bookID: bookID) }
        } catch {
            AppLogger.log(tag: "HighlightStore", "Error updating highlight color: \(error)")
        }
    }

    func highlights(forBookID bookID: UUID) -> [Highlight] {
        do {
            return try dbQueue.read { db in
                try Highlight
                    .filter(Column("bookID") == bookID && Column("deletedAt") == nil)
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "HighlightStore", "Error fetching highlights: \(error)")
            return []
        }
    }

    /// All non-deleted highlights across every book, newest first.
    func allHighlights() -> [Highlight] {
        do {
            return try dbQueue.read { db in
                try Highlight
                    .filter(Column("deletedAt") == nil)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "HighlightStore", "Error fetching all highlights: \(error)")
            return []
        }
    }

    private func notifyChange(bookID: UUID) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: bookID
            )
        }
    }

    // One-time import of highlights persisted in the legacy highlights.json file.
    private func migrateFromJSONIfNeeded() {
        let fm = FileManager.default
        guard
            let appSupport = try? fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        else { return }

        let jsonURL = appSupport.appendingPathComponent("highlights.json")
        guard fm.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let legacy = try? JSONDecoder().decode([Highlight].self, from: data),
              !legacy.isEmpty
        else {
            try? fm.removeItem(at: jsonURL)
            return
        }

        do {
            try dbQueue.write { db in
                for highlight in legacy {
                    // Skip if already imported (idempotent).
                    if try Highlight.fetchOne(db, id: highlight.id) == nil {
                        try highlight.insert(db)
                    }
                }
            }
            AppLogger.log(tag: "HighlightStore", "Migrated \(legacy.count) highlights from JSON to SQLite")
        } catch {
            AppLogger.log(tag: "HighlightStore", "JSON migration failed: \(error)")
        }

        try? fm.removeItem(at: jsonURL)
    }
}
