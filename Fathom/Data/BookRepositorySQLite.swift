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

        do {
            try await dbQueue.write { db in
                if var existing = try ReadingActivity.fetchOne(
                    db,
                    sql: "SELECT * FROM readingActivity WHERE bookID = ? AND date = ?",
                    arguments: [bookID.uuidString, todayStr]
                ) {
                    existing.duration += duration
                    try existing.update(db)
                } else {
                    let newActivity = ReadingActivity(
                        id: UUID(), bookID: bookID, date: todayStr,
                        duration: duration, createdAt: Date())
                    try newActivity.insert(db)
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
                if var existing = try ReadingActivity.fetchOne(
                    db,
                    sql: "SELECT * FROM readingActivity WHERE bookID = ? AND date = ?",
                    arguments: [activity.bookID.uuidString, activity.date]
                ) {
                    existing.duration += activity.duration
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
