import Foundation
import GRDB
import Testing

@testable import Fathom

/// The CDC triggers are the only producer of `cloudkit_pending_changes`, and
/// what they write has to be a usable CloudKit record name. These tests go
/// through the triggers rather than constructing rows directly — the previous
/// suite exercised the record layer in isolation, which is exactly why a
/// blob-in-a-text-column defect survived it.
struct CDCQueueTests {

    nonisolated private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    nonisolated private func queued(_ dbQueue: DatabaseQueue) throws -> [PendingChangeRow] {
        try dbQueue.read { db in
            try PendingChangeRow.fetchAll(db, sql: """
                SELECT recordType, recordID, operation, queuedAt
                FROM cloudkit_pending_changes ORDER BY recordType
                """)
        }
    }

    nonisolated private func insertBook(_ dbQueue: DatabaseQueue) throws -> Book {
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try dbQueue.write { db in try book.insert(db) }
        return book
    }

    // MARK: - The defect

    @Test("A queued recordID is canonical UUID text, not a raw blob")
    func recordIDIsText() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)

        let storedType = try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT typeof(recordID) FROM cloudkit_pending_changes
                WHERE recordType = 'Book'
                """)
        }
        // GRDB writes UUID as a blob and SQLite's TEXT affinity does not
        // convert it, so `NEW.id` straight into the column left 16 raw bytes.
        #expect(storedType == "text")

        let rows = try queued(dbQueue)
        #expect(rows.contains { $0.recordType == "Book" && $0.recordID == book.id.uuidString })
    }

    @Test("A queued recordID survives the round trip into a CloudKit record name")
    func recordIDBuildsAUsableRecordName() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)

        let row = try #require(try queued(dbQueue).first { $0.recordType == "Book" })
        let name = CKRecordName.make(type: row.recordType, localID: row.recordID)
        let parsed = try #require(CKRecordName.parse(name))

        #expect(parsed.type == CKRecordType.book)
        // The push path does exactly this, and returned nil for every record
        // while the id was mojibake — so nothing local could ever upload.
        #expect(UUID(uuidString: parsed.localID) == book.id)
    }

    @Test("Every CDC-tracked table queues a parseable id")
    func allTrackedTablesQueueParseableIDs() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)

        try dbQueue.write { db in
            try BookCategory(id: UUID(), name: "Sky", shelfColorHex: "112233",
                             createdAt: Date()).insert(db)
            try Highlight(id: UUID(), bookID: book.id, locatorJSON: "{}",
                          text: "a line", createdAt: Date(), color: .yellow).insert(db)
            try Bookmark(id: UUID(), bookID: book.id, locatorJSON: "{}",
                         progression: 0.5, createdAt: Date()).insert(db)
            try ReadingActivity(id: UUID(), bookID: book.id, date: "2026-08-21",
                                duration: 60, createdAt: Date()).insert(db)
        }

        for row in try queued(dbQueue) where row.recordType != "BookCategoryMembership" {
            #expect(UUID(uuidString: row.recordID) != nil,
                    "\(row.recordType) queued an unparseable id: \(row.recordID)")
        }
    }

    // MARK: - Composite membership key

    @Test("Membership keys join with an underscore and parse back")
    func membershipKeyIsLegalAndParses() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)
        let category = BookCategory(id: UUID(), name: "Sky",
                                    shelfColorHex: "112233", createdAt: Date())

        try dbQueue.write { db in
            try category.insert(db)
            try BookCategoryMembership(bookID: book.id, categoryID: category.id,
                                       addedAt: Date()).insert(db)
        }

        let row = try #require(
            try queued(dbQueue).first { $0.recordType == "BookCategoryMembership" })

        // "|" is not among the characters CloudKit accepts in a record name,
        // and CKRecordName splits on "_".
        #expect(!row.recordID.contains("|"))
        let parts = try #require(CKRecordName.parseMembership(localID: row.recordID))
        #expect(parts.bookID == book.id)
        #expect(parts.categoryID == category.id)
    }

    @Test("Record names the triggers produce use only legal characters")
    func queuedNamesUseLegalCharacters() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)
        let category = BookCategory(id: UUID(), name: "Sky",
                                    shelfColorHex: "112233", createdAt: Date())
        try dbQueue.write { db in
            try category.insert(db)
            try BookCategoryMembership(bookID: book.id, categoryID: category.id,
                                       addedAt: Date()).insert(db)
        }

        let legal = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        for row in try queued(dbQueue) {
            let name = CKRecordName.make(type: row.recordType, localID: row.recordID)
            #expect(name.unicodeScalars.allSatisfy { legal.contains($0) },
                    "illegal characters in \(name)")
        }
    }

    // MARK: - Deletes

    @Test("Deleting a book queues a delete carrying a parseable id")
    func hardDeleteQueuesParseableID() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)

        try dbQueue.write { db in _ = try Book.deleteOne(db, key: book.id) }

        let row = try #require(try queued(dbQueue).first { $0.recordType == "Book" })
        #expect(row.operation == "delete")
        #expect(row.recordID == book.id.uuidString)
    }

    // MARK: - Text ids

    @Test("An id already stored as text is passed through unchanged")
    func textIDsArePassedThrough() throws {
        let dbQueue = try makeMigratedQueue()
        let id = UUID()

        // touchLastReadAt carries a both-encodings fallback, so rows whose id
        // is text rather than a blob may exist; hex() would mangle those.
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO books (id, title, format, importDate, preprocessingStatus,
                                       aiAnalysisProgress, aiEnabled, modifiedAt)
                    VALUES (?, 'Text Id', 'epub', ?, 'pending', 0, 0, ?)
                    """,
                arguments: [id.uuidString, Date(), Date()])
        }

        let row = try #require(try queued(dbQueue).first { $0.recordType == "Book" })
        #expect(row.recordID == id.uuidString)
    }
}
