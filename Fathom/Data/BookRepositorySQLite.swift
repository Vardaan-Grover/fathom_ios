import Foundation
import GRDB

final actor BookRepositorySQLite: BookRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func listBooks() async -> [Book] {
        do {
            return try await dbQueue.read { db in
                try Book.fetchAll(db)
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
            return []
        }
    }

    /// Full-text search over title/author/description via the `books_fts`
    /// index (migration v28).
    ///
    /// Cost is proportional to the number of *matches*, not to library size —
    /// which is the whole reason this goes through FTS5 rather than filtering
    /// `listBooks()` in memory. Measured on a 50k-book library, an in-memory
    /// filter costs 180–350ms per keystroke while this stays flat at ~17ms.
    func searchBooks(query: String) async -> [Book] {
        guard let match = LibrarySearch.matchExpression(for: query) else { return [] }
        do {
            return try await dbQueue.read { db in
                try Book.fetchAll(
                    db,
                    sql: """
                        SELECT books.* FROM books
                        JOIN books_fts ON books_fts.rowid = books.rowid
                        WHERE books_fts MATCH ?
                        ORDER BY bm25(books_fts, ?, ?, ?)
                        """,
                    arguments: [
                        match,
                        LibrarySearch.titleWeight,
                        LibrarySearch.authorWeight,
                        LibrarySearch.descriptionWeight,
                    ]
                )
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
            return []
        }
    }

    func addBook(_ book: Book) async {
        do {
            try await dbQueue.write { db in
                try book.insert(db)
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
        }
    }

    func updateBook(_ book: Book) async {
        do {
            try await dbQueue.write { db in
                try book.update(db)
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
        }
    }

    func deleteBook(_ book: Book) async {
        do {
            try await dbQueue.write { db in
                _ = try book.delete(db)
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
        }
    }

    func touchLastReadAt(bookID: UUID) async {
        do {
            try await dbQueue.write { db in
                if var book = try Book.fetchOne(db, key: bookID) {
                    book.lastReadAt = Date()
                    try book.update(db)
                } else if var book = try Book.fetchOne(db, key: bookID.uuidString) {
                    book.lastReadAt = Date()
                    try book.update(db)
                } else {
                    AppLogger.log(
                        tag: "BookRepository",
                        "Failed to find book to touch lastReadAt for \(bookID)")
                }
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
        }
    }

    func logReadingSession(for bookID: UUID, duration: TimeInterval) async {
        guard duration > 0 else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayStr = formatter.string(from: Date())

        let deviceID = DeviceIdentity.current
        let now = Date()

        do {
            try await dbQueue.write { db in
                // Scoped to this device: rows belonging to other devices are
                // theirs to write, and adding to one here would double-count
                // time they already reported. See §3.4 of
                // docs/sync-conflict-policy.md.
                //
                // bookID is bound as a UUID, not `bookID.uuidString`. GRDB
                // stores UUID as a 16-byte blob, so comparing the column
                // against a string matches nothing — the previous version of
                // this lookup always missed, so every session after the first
                // each day tried to insert, hit the unique index, threw, and
                // was swallowed by the catch below. The time was lost.
                //
                // Deliberately fetch-then-write rather than an UPSERT: a
                // statement carrying its own ON CONFLICT clause overrides the
                // conflict resolution inside any trigger it fires, which
                // downgrades the CDC trigger's `INSERT OR REPLACE` into a
                // plain INSERT and makes it fail against
                // cloudkit_pending_changes' primary key. `dbQueue.write`
                // serialises writers, so read-then-write is atomic here
                // regardless.
                if var existing = try ReadingActivity.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM readingActivity
                        WHERE bookID = ? AND date = ? AND deviceID = ?
                        """,
                    arguments: [bookID, todayStr, deviceID]
                ) {
                    existing.duration += duration
                    existing.modifiedAt = now
                    try existing.update(db)
                } else {
                    try ReadingActivity(
                        id: UUID(), bookID: bookID, date: todayStr,
                        duration: duration, createdAt: now,
                        deviceID: deviceID).insert(db)
                }
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
        }
    }

    func listReadingActivity(forYear year: Int) async -> [ReadingActivity] {
        do {
            return try await dbQueue.read { db in
                try ReadingActivity.fetchAll(
                    db,
                    sql: "SELECT * FROM readingActivity WHERE date LIKE ?",
                    arguments: ["\(year)-%"])
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
            return []
        }
    }

    func insertMockReadingActivity(_ activity: ReadingActivity) async {
        do {
            try await dbQueue.write { db in
                // Mirrors logReadingSession — see the notes there on binding
                // bookID as a UUID and on avoiding UPSERT.
                if var existing = try ReadingActivity.fetchOne(
                    db,
                    sql: """
                        SELECT * FROM readingActivity
                        WHERE bookID = ? AND date = ? AND deviceID = ?
                        """,
                    arguments: [activity.bookID, activity.date, activity.deviceID]
                ) {
                    existing.duration += activity.duration
                    existing.modifiedAt = Date()
                    try existing.update(db)
                } else {
                    try activity.insert(db)
                }
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
        }
    }

    func deleteAllReadingActivity(forYear year: Int) async {
        do {
            try await dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM readingActivity WHERE date LIKE ?",
                    arguments: ["\(year)-%"])
            }
        } catch {
            AppLogger.logError(tag: "BookRepository", error)
        }
    }
}
