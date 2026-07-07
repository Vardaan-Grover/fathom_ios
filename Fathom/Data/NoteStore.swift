import Foundation
import GRDB

final class NoteStore {
    static let shared = NoteStore()

    /// Posted on the main queue after any write (add, update, delete) commits.
    /// `object` is the affected `bookID: UUID`.
    static let didChangeNotification = Notification.Name("NoteStore.didChange")

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    private init() {}

    // Writes are asynchronous so callers (often on the main thread, e.g. the
    // reader's edit menu) never block on the database — observers refresh via
    // didChangeNotification once the write commits.

    func add(_ note: Note) {
        dbQueue.asyncWrite({ db in
            try note.insert(db)
        }, completion: { _, result in
            switch result {
            case .success:
                Self.notifyChange(bookID: note.bookID)
            case .failure(let error):
                AppLogger.log(tag: "NoteStore", "Error adding note: \(error)")
            }
        })
    }

    func delete(id: UUID) {
        dbQueue.asyncWrite({ db -> UUID? in
            guard var note = try Note.fetchOne(db, id: id) else { return nil }
            note.deletedAt = Date()
            try note.update(db)
            return note.bookID
        }, completion: { _, result in
            switch result {
            case .success(let bookID):
                if let bookID { Self.notifyChange(bookID: bookID) }
            case .failure(let error):
                AppLogger.log(tag: "NoteStore", "Error soft-deleting note: \(error)")
            }
        })
    }

    func update(_ note: Note) {
        dbQueue.asyncWrite({ db in
            try note.update(db)
        }, completion: { _, result in
            switch result {
            case .success:
                Self.notifyChange(bookID: note.bookID)
            case .failure(let error):
                AppLogger.log(tag: "NoteStore", "Error updating note: \(error)")
            }
        })
    }

    func updateContent(id: UUID, content: String) {
        dbQueue.asyncWrite({ db -> UUID? in
            guard var note = try Note.fetchOne(db, id: id) else { return nil }
            note.noteContent = content
            try note.update(db)
            return note.bookID
        }, completion: { _, result in
            switch result {
            case .success(let bookID):
                if let bookID { Self.notifyChange(bookID: bookID) }
            case .failure(let error):
                AppLogger.log(tag: "NoteStore", "Error updating note content: \(error)")
            }
        })
    }

    func updateHighlightColor(id: UUID, color: HighlightColor) {
        dbQueue.asyncWrite({ db -> UUID? in
            guard var note = try Note.fetchOne(db, id: id) else { return nil }
            note.highlightColor = color
            try note.update(db)
            return note.bookID
        }, completion: { _, result in
            switch result {
            case .success(let bookID):
                if let bookID { Self.notifyChange(bookID: bookID) }
            case .failure(let error):
                AppLogger.log(tag: "NoteStore", "Error updating note color: \(error)")
            }
        })
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

    /// All non-deleted notes across every book, newest first.
    func allNotes() -> [Note] {
        do {
            return try dbQueue.read { db in
                try Note
                    .filter(Column("deletedAt") == nil)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "NoteStore", "Error fetching all notes: \(error)")
            return []
        }
    }

    private static func notifyChange(bookID: UUID) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: bookID
            )
        }
    }
}
