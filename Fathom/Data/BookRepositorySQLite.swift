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
}
