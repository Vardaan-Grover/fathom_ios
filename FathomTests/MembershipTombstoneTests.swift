import CloudKit
import Foundation
import GRDB
import Testing

@testable import Fathom

/// Shelf membership is a two-phase set: removal is a tombstone, and a
/// tombstone is final until an explicit re-add clears it. See §3.3 of
/// docs/sync-conflict-policy.md.
struct MembershipTombstoneTests {

    nonisolated private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    nonisolated private func seed(_ dbQueue: DatabaseQueue) throws -> (Book, BookCategory) {
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        let category = BookCategory(id: UUID(), name: "Sky",
                                    shelfColorHex: "112233", createdAt: Date())
        try dbQueue.write { db in
            try book.insert(db)
            try category.insert(db)
        }
        return (book, category)
    }

    nonisolated private func rawRows(_ dbQueue: DatabaseQueue) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bookCategoryMemberships") ?? 0
        }
    }

    // MARK: - Removal

    @Test("Removing a book from a shelf tombstones the row instead of deleting it")
    func removalTombstones() async throws {
        let dbQueue = try makeMigratedQueue()
        let (book, category) = try seed(dbQueue)
        let repo = CategoryRepositorySQLite(dbQueue: dbQueue)

        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)
        await repo.removeBookFromCategory(bookID: book.id, categoryID: category.id)

        // The row survives — a hard delete carries no evidence it happened, so
        // a device offline during the removal would re-add the book.
        #expect(try rawRows(dbQueue) == 1)
        let deletedAt = try await dbQueue.read { db in
            try Date.fetchOne(db, sql: "SELECT deletedAt FROM bookCategoryMemberships")
        }
        #expect(deletedAt != nil)
    }

    @Test("A tombstoned membership is not on the shelf")
    func tombstonesAreNotListed() async throws {
        let dbQueue = try makeMigratedQueue()
        let (book, category) = try seed(dbQueue)
        let repo = CategoryRepositorySQLite(dbQueue: dbQueue)

        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)
        #expect(await repo.listMemberships().count == 1)

        await repo.removeBookFromCategory(bookID: book.id, categoryID: category.id)
        #expect(await repo.listMemberships().isEmpty)
    }

    @Test("Removal queues an upsert, not a delete")
    func removalQueuesAnUpsert() async throws {
        let dbQueue = try makeMigratedQueue()
        let (book, category) = try seed(dbQueue)
        let repo = CategoryRepositorySQLite(dbQueue: dbQueue)

        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)
        await repo.removeBookFromCategory(bookID: book.id, categoryID: category.id)

        let row = try await dbQueue.read { db in
            try PendingChangeRow.fetchAll(db, sql: """
                SELECT recordType, recordID, operation, queuedAt
                FROM cloudkit_pending_changes WHERE recordType = 'BookCategoryMembership'
                """)
        }.first
        let queued = try #require(row)
        // The tombstone travels as a field on the record; deleting the CloudKit
        // record would throw the evidence away again.
        #expect(queued.operation == "upsert")
        #expect(CKRecordName.parseMembership(localID: queued.recordID)?.bookID == book.id)
    }

    // MARK: - Re-adding

    @Test("Re-adding a removed book puts it back on the shelf")
    func readdClearsTheTombstone() async throws {
        let dbQueue = try makeMigratedQueue()
        let (book, category) = try seed(dbQueue)
        let repo = CategoryRepositorySQLite(dbQueue: dbQueue)

        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)
        await repo.removeBookFromCategory(bookID: book.id, categoryID: category.id)
        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)

        // The primary key means a plain insert would be ignored, leaving the
        // book permanently off the shelf.
        #expect(await repo.listMemberships().count == 1)
        #expect(try rawRows(dbQueue) == 1)
    }

    @Test("Adding a book that is already on the shelf is a no-op")
    func duplicateAddIsHarmless() async throws {
        let dbQueue = try makeMigratedQueue()
        let (book, category) = try seed(dbQueue)
        let repo = CategoryRepositorySQLite(dbQueue: dbQueue)

        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)
        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)

        #expect(try rawRows(dbQueue) == 1)
        #expect(await repo.listMemberships().count == 1)
    }

    // MARK: - Reordering

    @Test("Reordering a shelf does not resurrect a removed book")
    func reorderDoesNotResurrect() async throws {
        let dbQueue = try makeMigratedQueue()
        let (book, category) = try seed(dbQueue)
        let other = Book(id: UUID(), title: "Pale Blue Dot", author: "Sagan", format: .epub)
        try await dbQueue.write { db in try other.insert(db) }
        let repo = CategoryRepositorySQLite(dbQueue: dbQueue)

        await repo.addBookToCategory(bookID: book.id, categoryID: category.id)
        await repo.addBookToCategory(bookID: other.id, categoryID: category.id)
        await repo.removeBookFromCategory(bookID: book.id, categoryID: category.id)

        await repo.reorderBooksInCategory(categoryID: category.id,
                                          bookIDs: [book.id, other.id])

        let listed = await repo.listMemberships()
        #expect(listed.count == 1)
        #expect(listed.first?.bookID == other.id)
    }

    // MARK: - Sync

    @Test("deletedAt survives the CloudKit round trip")
    func tombstoneRoundTrips() throws {
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let membership = BookCategoryMembership(
            bookID: UUID(), categoryID: UUID(), addedAt: Date(),
            sortOrder: 2, modifiedAt: Date(), deletedAt: deletedAt)

        let decoded = try #require(
            BookCategoryMembership.from(ckRecord: membership.toCKRecord(zoneID: zoneID)))
        #expect(decoded.deletedAt == deletedAt)
        #expect(decoded.bookID == membership.bookID)
    }

    @Test("A removal beats a concurrent reorder on the other device")
    func tombstoneBeatsConcurrentEdit() throws {
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let localID = CKRecordName.membershipLocalID(bookID: UUID(), categoryID: UUID())
        let recordID = CKRecordName.id(type: CKRecordType.bookCategoryMembership,
                                       localID: localID, zoneID: zoneID)
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let ancestor = CKRecord(recordType: CKRecordType.bookCategoryMembership,
                                recordID: recordID)
        ancestor["sortOrder"] = 1

        // This device reordered the shelf.
        let client = CKRecord(recordType: CKRecordType.bookCategoryMembership,
                              recordID: recordID)
        client["sortOrder"] = 5

        // The other device took the book off the shelf.
        let server = CKRecord(recordType: CKRecordType.bookCategoryMembership,
                              recordID: recordID)
        server["sortOrder"] = 1
        server["deletedAt"] = deletedAt

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
        #expect(merged["deletedAt"] as? Date == deletedAt)
    }

    // MARK: - Schema

    @Test("The membership table has an update trigger")
    func updateTriggerExists() throws {
        // Removal is an UPDATE now; without this trigger it would never be
        // queued for sync at all.
        let triggers = try makeMigratedQueue().read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'")
        }
        #expect(triggers.contains("bookCategoryMemberships_ck_update"))
        #expect(triggers.contains("bookCategoryMemberships_ck_insert"))
        // Still needed: the foreign keys cascade when a book or shelf is
        // deleted outright, and those really should remove the record.
        #expect(triggers.contains("bookCategoryMemberships_ck_delete"))
    }
}

/// The v33 split of completion data out of `books`. Migration v33 carries
/// existing ratings and reflections across, so this covers the data move as
/// well as the resulting shape. See §3.1 of docs/sync-conflict-policy.md.
struct BookCompletionSplitTests {

    nonisolated private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    @Test("Existing ratings and reflections survive the split")
    func migrationCarriesExistingCompletions() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)

        // Stop just before the split, so the old shape is what we write into.
        try DatabaseManager.makeMigrator()
            .migrate(dbQueue, upTo: "v32_membership_tombstones")

        let finishedID = UUID()
        let ratedOnlyID = UUID()
        let untouchedID = UUID()
        let finishedAt = Date(timeIntervalSince1970: 1_760_000_000)

        try dbQueue.write { db in
            for (id, rating, reflection, finished) in [
                (finishedID, 5 as Int?, "Changed how I read." as String?, finishedAt as Date?),
                (ratedOnlyID, 3, nil, nil),
                (untouchedID, nil, nil, nil),
            ] {
                try db.execute(
                    sql: """
                        INSERT INTO books (id, title, format, importDate, preprocessingStatus,
                                           aiAnalysisProgress, aiEnabled, modifiedAt,
                                           rating, reflection, finishedAt)
                        VALUES (?, 'Cosmos', 'epub', ?, 'pending', 0, 0, ?, ?, ?, ?)
                        """,
                    arguments: [id, Date(), Date(), rating, reflection, finished])
            }
        }

        try DatabaseManager.makeMigrator().migrate(dbQueue)

        let completions = try dbQueue.read { db in
            try BookCompletion.fetchAll(db)
        }
        // The finished book and the rated-but-unfinished one both carry reader
        // data and must survive; the untouched book has nothing to carry.
        #expect(completions.count == 2)

        let finishedRow = try #require(completions.first { $0.bookID == finishedID })
        #expect(finishedRow.rating == 5)
        #expect(finishedRow.reflection == "Changed how I read.")
        #expect(finishedRow.finishedAt == finishedAt)

        let ratedRow = try #require(completions.first { $0.bookID == ratedOnlyID })
        #expect(ratedRow.rating == 3)
        // No finish date was ever recorded, so it adopts the book's modifiedAt
        // rather than inventing one.
        #expect(ratedRow.reflection == nil)

        #expect(!completions.contains { $0.bookID == untouchedID })
    }

    @Test("books no longer carries completion columns")
    func booksHasNoCompletionColumns() throws {
        let columns = try makeMigratedQueue().read { db in
            try db.columns(in: "books").map(\.name)
        }
        for dropped in ["rating", "reflection", "reflectionImageFilename", "finishedAt"] {
            #expect(!columns.contains(dropped), "books still has \(dropped)")
        }
    }

    @Test("A completion is queued for sync under its own record type")
    func completionQueuesItsOwnRecord() async throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try await dbQueue.write { db in try book.insert(db) }
        let repo = BookRepositorySQLite(dbQueue: dbQueue)

        await repo.saveCompletion(
            BookCompletion(bookID: book.id, rating: 4, reflection: "Good.",
                           finishedAt: Date()))

        let queued = try await dbQueue.read { db in
            try PendingChangeRow.fetchAll(db, sql: """
                SELECT recordType, recordID, operation, queuedAt
                FROM cloudkit_pending_changes WHERE recordType = 'BookCompletion'
                """)
        }
        let row = try #require(queued.first)
        #expect(UUID(uuidString: row.recordID) == book.id)
        #expect(row.operation == "upsert")
    }

    @Test("Deleting a book takes its completion with it")
    func completionCascades() async throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try await dbQueue.write { db in try book.insert(db) }
        let repo = BookRepositorySQLite(dbQueue: dbQueue)

        await repo.saveCompletion(BookCompletion(bookID: book.id, finishedAt: Date()))
        #expect(await repo.completion(forBookID: book.id) != nil)

        await repo.deleteBook(book)
        #expect(await repo.completion(forBookID: book.id) == nil)

        // The cascade must queue a CloudKit delete, or the record outlives the
        // book on every other device.
        let deletes = try await dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT operation FROM cloudkit_pending_changes
                WHERE recordType = 'BookCompletion'
                """)
        }
        #expect(deletes.contains("delete"))
    }

    @Test("Saving a completion twice updates rather than duplicating")
    func saveIsIdempotent() async throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try await dbQueue.write { db in try book.insert(db) }
        let repo = BookRepositorySQLite(dbQueue: dbQueue)

        let finishedAt = Date(timeIntervalSince1970: 1_760_000_000)
        await repo.saveCompletion(
            BookCompletion(bookID: book.id, rating: 3, finishedAt: finishedAt))
        await repo.saveCompletion(
            BookCompletion(bookID: book.id, rating: 5, finishedAt: finishedAt))

        let rows = try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bookCompletions") ?? 0
        }
        #expect(rows == 1)
        #expect(await repo.completion(forBookID: book.id)?.rating == 5)
    }

    @Test("Clearing a rating is representable, not swallowed")
    func ratingCanBeCleared() async throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try await dbQueue.write { db in try book.insert(db) }
        let repo = BookRepositorySQLite(dbQueue: dbQueue)
        let finishedAt = Date()

        await repo.saveCompletion(
            BookCompletion(bookID: book.id, rating: 5, reflection: "Good.",
                           finishedAt: finishedAt))
        await repo.saveCompletion(
            BookCompletion(bookID: book.id, rating: nil, reflection: nil,
                           finishedAt: finishedAt))

        let stored = try #require(await repo.completion(forBookID: book.id))
        #expect(stored.rating == nil)
        #expect(stored.reflection == nil)
    }
}
