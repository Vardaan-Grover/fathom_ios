import Foundation
import GRDB
import Testing

@testable import Fathom

/// Runs the full production migration chain against in-memory databases and
/// verifies the schema invariants the sync engine depends on.
struct MigrationTests {

    private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    private func triggerNames(_ dbQueue: DatabaseQueue) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'")
        }
    }

    @Test func migrationChainCompletesOnFreshDatabase() throws {
        let dbQueue = try makeMigratedQueue()
        let tables = try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        for expected in [
            "books", "chapters", "paragraphs", "bookCategories",
            "bookCategoryMemberships", "highlights", "notes", "bookmarks",
            "saved_words", "readingActivity", "cloudkit_pending_changes",
        ] {
            #expect(tables.contains(expected), "missing table \(expected)")
        }
    }

    @Test func aiConversationSyncTriggersAreDropped() throws {
        // v26 drops the AI CDC triggers (AI Companion is dormant).
        let triggers = try triggerNames(makeMigratedQueue())
        #expect(!triggers.contains("aiConversations_ck_insert"))
        #expect(!triggers.contains("aiConversations_ck_update"))
        #expect(!triggers.contains("aiConversations_ck_delete"))
        #expect(!triggers.contains("aiMessages_ck_insert"))
    }

    @Test func cdcTriggersExistForSyncedTables() throws {
        let triggers = try triggerNames(makeMigratedQueue())
        for table in ["books", "bookCategories", "highlights", "notes",
                      "bookmarks", "saved_words", "readingActivity"] {
            #expect(triggers.contains("\(table)_ck_insert"), "missing insert trigger for \(table)")
            #expect(triggers.contains("\(table)_ck_update"), "missing update trigger for \(table)")
        }
        #expect(triggers.contains("books_ck_delete"))
        #expect(triggers.contains("bookCategoryMemberships_ck_insert"))
        #expect(triggers.contains("bookCategoryMemberships_ck_delete"))
    }

    @Test func insertQueuesCloudKitChangeWithMillisecondTimestamp() throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = UUID().uuidString
        let highlightID = UUID().uuidString

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO books (id, title, format, importDate, preprocessingStatus, aiAnalysisProgress)
                VALUES (?, 'Test', 'epub', '2026-01-01 00:00:00', 'pending', 0)
                """, arguments: [bookID])
            try db.execute(sql: """
                INSERT INTO highlights (id, bookID, locatorJSON, text, createdAt, color)
                VALUES (?, ?, '{}', 'hello', '2026-01-01 00:00:00', 'yellow')
                """, arguments: [highlightID, bookID])
        }

        let row = try dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT recordType, operation, queuedAt FROM cloudkit_pending_changes
                WHERE recordID = ?
                """, arguments: [highlightID])
        }
        let queuedAt: String = try #require(row?["queuedAt"])
        #expect(row?["recordType"] == "Highlight")
        #expect(row?["operation"] == "upsert")
        // v27 triggers stamp millisecond-precision ISO timestamps — the exact-
        // match queue cleanup depends on this format.
        #expect(queuedAt.contains("T"))
        #expect(queuedAt.contains("."))
    }

    @Test func requeueDuringPushProducesNewTimestamp() throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = UUID().uuidString

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO books (id, title, format, importDate, preprocessingStatus, aiAnalysisProgress)
                VALUES (?, 'Test', 'epub', '2026-01-01 00:00:00', 'pending', 0)
                """, arguments: [bookID])
        }
        let first: String? = try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT queuedAt FROM cloudkit_pending_changes WHERE recordID = ?
                """, arguments: [bookID])
        }

        // Simulate an edit landing while the row's push is in flight.
        Thread.sleep(forTimeInterval: 0.01)
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE books SET title = 'Edited' WHERE id = ?",
                           arguments: [bookID])
        }
        let second: String? = try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT queuedAt FROM cloudkit_pending_changes WHERE recordID = ?
                """, arguments: [bookID])
        }

        #expect(first != nil && second != nil)
        // A fresh timestamp means the exact-match cleanup of the pushed row
        // won't delete the re-queued change.
        #expect(first != second)
    }

    @Test func deleteQueuesDeleteOperation() throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = UUID().uuidString

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO books (id, title, format, importDate, preprocessingStatus, aiAnalysisProgress)
                VALUES (?, 'Test', 'epub', '2026-01-01 00:00:00', 'pending', 0)
                """, arguments: [bookID])
            try db.execute(sql: "DELETE FROM books WHERE id = ?", arguments: [bookID])
        }

        let operation: String? = try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT operation FROM cloudkit_pending_changes WHERE recordID = ?
                """, arguments: [bookID])
        }
        #expect(operation == "delete")
    }
}
