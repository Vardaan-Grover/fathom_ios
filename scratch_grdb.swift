import Foundation
import GRDB

// Load the Book struct exactly as it is in the project
struct Book: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "books"

    let id: UUID
    let title: String
    var author: String?
    var contentHash: String? = nil
}

do {
    let dbQueue = try DatabaseQueue(path: "fathom.sqlite")
    let books = try dbQueue.read { db in
        try Book.fetchAll(db)
    }
    for b in books {
        print("Title: \(b.title), Hash: \(b.contentHash ?? "nil")")
    }
} catch {
    print("Error: \(error)")
}
