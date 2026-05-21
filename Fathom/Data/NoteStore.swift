import Foundation
import GRDB

final class NoteStore {
    static let shared = NoteStore()

    /// Posted on the main queue after any write (add, update, delete).
    /// `object` is the affected `bookID: UUID`.
    static let didChangeNotification = Notification.Name("NoteStore.didChange")

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    private init() {}

    func add(_ note: Note) {
        do {
            try dbQueue.write { db in
                try note.insert(db)
            }
            notifyChange(bookID: note.bookID)
        } catch {
            AppLogger.log(tag: "NoteStore", "Error adding note: \(error)")
        }
    }

    func delete(id: UUID) {
        var bookID: UUID?
        do {
            try dbQueue.write { db in
                if var note = try Note.fetchOne(db, id: id) {
                    bookID = note.bookID
                    note.deletedAt = Date()
                    try note.update(db)
                }
            }
            if let bookID { notifyChange(bookID: bookID) }
        } catch {
            AppLogger.log(tag: "NoteStore", "Error soft-deleting note: \(error)")
        }
    }

    func update(_ note: Note) {
        do {
            try dbQueue.write { db in
                try note.update(db)
            }
            notifyChange(bookID: note.bookID)
        } catch {
            AppLogger.log(tag: "NoteStore", "Error updating note: \(error)")
        }
    }

    func updateContent(id: UUID, content: String) {
        var affectedBookID: UUID?
        do {
            try dbQueue.write { db in
                if var note = try Note.fetchOne(db, id: id) {
                    note.noteContent = content
                    try note.update(db)
                    affectedBookID = note.bookID
                }
            }
            if let bookID = affectedBookID { notifyChange(bookID: bookID) }
        } catch {
            AppLogger.log(tag: "NoteStore", "Error updating note content: \(error)")
        }
    }

    func updateHighlightColor(id: UUID, color: HighlightColor) {
        var affectedBookID: UUID?
        do {
            try dbQueue.write { db in
                if var note = try Note.fetchOne(db, id: id) {
                    note.highlightColor = color
                    try note.update(db)
                    affectedBookID = note.bookID
                }
            }
            if let bookID = affectedBookID { notifyChange(bookID: bookID) }
        } catch {
            AppLogger.log(tag: "NoteStore", "Error updating note color: \(error)")
        }
    }

    func notes(forBookID bookID: UUID) -> [Note] {
        do {
            return try dbQueue.read { db in
                try Note
                    .filter(Column("bookID") == bookID && Column("deletedAt") == nil)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "NoteStore", "Error fetching notes: \(error)")
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
}
