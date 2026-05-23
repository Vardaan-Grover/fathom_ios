import Foundation
import GRDB

final actor BookRepositorySQLite: BookRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func listBooks() async -> [Book] {
        await withCheckedContinuation { continuation in
            do {
                let books = try dbQueue.read { db in
                    try Book.fetchAll(db)
                }
                continuation.resume(returning: books)
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    func addBook(_ book: Book) async {
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in
                    try book.insert(db)
                }
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "BookRepository", error)
                continuation.resume()
            }
        }
    }

    func updateBook(_ book: Book) async {
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in try book.update(db) }
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "BookRepository", error)
                continuation.resume()
            }
        }
    }

    func deleteBook(_ book: Book) async {
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in
                    _ = try book.delete(db)
                }
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "BookRepository", error)
                continuation.resume()
            }
        }
    }

    func touchLastReadAt(bookID: UUID) async {
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in
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
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "BookRepository", error)
                continuation.resume()
            }
        }
    }

    func logReadingSession(for bookID: UUID, duration: TimeInterval) async {
        guard duration > 0 else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayStr = formatter.string(from: Date())
        
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in
                    if var existing = try ReadingActivity.fetchOne(db, sql: "SELECT * FROM readingActivity WHERE bookID = ? AND date = ?", arguments: [bookID.uuidString, todayStr]) {
                        existing.duration += duration
                        try existing.update(db)
                    } else {
                        let newActivity = ReadingActivity(id: UUID(), bookID: bookID, date: todayStr, duration: duration, createdAt: Date())
                        try newActivity.insert(db)
                    }
                }
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "BookRepository", error)
                continuation.resume()
            }
        }
    }

    func listReadingActivity(forYear year: Int) async -> [ReadingActivity] {
        await withCheckedContinuation { continuation in
            do {
                let prefix = "\(year)-"
                let activities = try dbQueue.read { db in
                    try ReadingActivity.fetchAll(db, sql: "SELECT * FROM readingActivity WHERE date LIKE ?", arguments: [prefix + "%"])
                }
                continuation.resume(returning: activities)
            } catch {
                AppLogger.logError(tag: "BookRepository", error)
                continuation.resume(returning: [])
            }
        }
    }

    func insertMockReadingActivity(_ activity: ReadingActivity) async {
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in
                    if var existing = try ReadingActivity.fetchOne(db, sql: "SELECT * FROM readingActivity WHERE bookID = ? AND date = ?", arguments: [activity.bookID.uuidString, activity.date]) {
                        existing.duration += activity.duration
                        try existing.update(db)
                    } else {
                        try activity.insert(db)
                    }
                }
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "BookRepository", error)
                continuation.resume()
            }
        }
    }
}
