import CloudKit
import Foundation
import GRDB
import Testing

@testable import Fathom

/// A child record arriving before its parent must be parked and retried, not
/// dropped. CloudKit does not redeliver, so a dropped record is gone for good.
/// See migration v34.
struct DeferredApplyTests {

    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    nonisolated private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    private func highlightRecord(bookID: UUID) -> CKRecord {
        let highlight = Highlight(id: UUID(), bookID: bookID, locatorJSON: "{}",
                                  text: "a line", createdAt: Date(), color: .yellow)
        return highlight.toCKRecord(zoneID: zoneID)
    }

    // MARK: - Parent detection

    @Test("A highlight whose book is absent is not ready to apply")
    func missingBookIsDetected() throws {
        let dbQueue = try makeMigratedQueue()
        let record = highlightRecord(bookID: UUID())

        let ready = try dbQueue.read { db in
            try SyncDeferredApplies.parentsExist(db: db, record: record)
        }
        #expect(!ready)
    }

    @Test("The same highlight is ready once its book exists")
    func presentBookIsDetected() throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try dbQueue.write { db in try book.insert(db) }

        let ready = try dbQueue.read { db in
            try SyncDeferredApplies.parentsExist(db: db, record: highlightRecord(bookID: book.id))
        }
        #expect(ready)
    }

    @Test("A membership needs both its book and its shelf")
    func membershipNeedsBothParents() throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        let category = BookCategory(id: UUID(), name: "Sky",
                                    shelfColorHex: "112233", createdAt: Date())
        let record = BookCategoryMembership(bookID: book.id, categoryID: category.id,
                                            addedAt: Date()).toCKRecord(zoneID: zoneID)

        try dbQueue.write { db in try book.insert(db) }
        #expect(try dbQueue.read { db in
            try SyncDeferredApplies.parentsExist(db: db, record: record)
        } == false, "the shelf is still missing")

        try dbQueue.write { db in try category.insert(db) }
        #expect(try dbQueue.read { db in
            try SyncDeferredApplies.parentsExist(db: db, record: record)
        })
    }

    private func savedWord(bookID: UUID?) -> SavedWord {
        SavedWord(id: UUID(), word: "w", language: "en", partsOfSpeech: "noun",
                  bookID: bookID, bookTitle: nil, chapter: nil, pageNumber: nil,
                  locatorJSON: nil, contextSentence: nil,
                  fullDictionaryJSON: nil, createdAt: Date())
    }

    @Test("A saved word pointing at an absent book is not applicable")
    func savedWordWithMissingBookIsDeferred() throws {
        // saved_words.bookID is nullable with ON DELETE SET NULL, which permits
        // NULL — it does not permit a non-NULL value pointing at a row that is
        // not there. Believing otherwise dropped 20 saved words on the first
        // clean install, with a bare FOREIGN KEY constraint failed in the log.
        let dbQueue = try makeMigratedQueue()
        let record = savedWord(bookID: UUID()).toCKRecord(zoneID: zoneID)

        #expect(try dbQueue.read { db in
            try SyncDeferredApplies.parentsExist(db: db, record: record)
        } == false)

        // And the insert really does fail, so the guard is load-bearing.
        #expect(throws: (any Error).self) {
            try dbQueue.write { db in
                try #require(SavedWord.from(ckRecord: record)).insert(db)
            }
        }
    }

    @Test("A saved word with no book at all is applicable")
    func savedWordWithoutBookApplies() throws {
        // A word can be saved outside any book; that is what the nullable
        // column is for, and it must not be parked forever waiting on nothing.
        let dbQueue = try makeMigratedQueue()
        let record = savedWord(bookID: nil).toCKRecord(zoneID: zoneID)

        #expect(try dbQueue.read { db in
            try SyncDeferredApplies.parentsExist(db: db, record: record)
        })
        try dbQueue.write { db in
            try #require(SavedWord.from(ckRecord: record)).insert(db)
        }
        #expect(try dbQueue.read { db in try SavedWord.fetchCount(db) } == 1)
    }

    // MARK: - Parking round trip

    @Test("A parked record round-trips with its values intact")
    func parkedRecordRoundTrips() throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = UUID()
        let record = highlightRecord(bookID: bookID)

        try dbQueue.write { db in try SyncDeferredApplies.park(db: db, record: record) }

        let parked = try dbQueue.read { db in try SyncDeferredApplies.pending(db: db) }
        let restored = try #require(parked.first)

        // Values, not just system fields — the record has to be applicable
        // later without re-fetching it.
        #expect(restored.recordID.recordName == record.recordID.recordName)
        #expect(restored["text"] as? String == "a line")
        #expect(restored["bookID"] as? String == bookID.uuidString)
        #expect(Highlight.from(ckRecord: restored)?.bookID == bookID)
    }

    @Test("Parking the same record twice keeps one row")
    func parkingIsIdempotent() throws {
        let dbQueue = try makeMigratedQueue()
        let record = highlightRecord(bookID: UUID())

        try dbQueue.write { db in
            try SyncDeferredApplies.park(db: db, record: record)
            try SyncDeferredApplies.park(db: db, record: record)
        }
        #expect(try dbQueue.read { db in try SyncDeferredApplies.count(db: db) } == 1)
    }

    @Test("Removing a parked record clears it")
    func removeClearsIt() throws {
        let dbQueue = try makeMigratedQueue()
        let record = highlightRecord(bookID: UUID())

        try dbQueue.write { db in
            try SyncDeferredApplies.park(db: db, record: record)
            try SyncDeferredApplies.remove(db: db, type: record.recordType,
                                           recordName: record.recordID.recordName)
        }
        #expect(try dbQueue.read { db in try SyncDeferredApplies.count(db: db) } == 0)
    }

    // MARK: - Pruning

    @Test("A record whose parent never arrives is eventually dropped")
    func staleRecordsArePruned() throws {
        let dbQueue = try makeMigratedQueue()
        let record = highlightRecord(bookID: UUID())
        try dbQueue.write { db in try SyncDeferredApplies.park(db: db, record: record) }

        // A parent can be permanently absent — the book was deleted on the
        // other device — and without a bound these rows accumulate forever.
        let wellPast = Date().addingTimeInterval(SyncDeferredApplies.maximumAge + 60)
        let pruned = try dbQueue.write { db in
            try SyncDeferredApplies.prune(db: db, now: wellPast)
        }
        #expect(pruned == 1)
        #expect(try dbQueue.read { db in try SyncDeferredApplies.count(db: db) } == 0)
    }

    @Test("A record still within the window is kept")
    func freshRecordsSurvivePruning() throws {
        let dbQueue = try makeMigratedQueue()
        try dbQueue.write { db in
            try SyncDeferredApplies.park(db: db, record: highlightRecord(bookID: UUID()))
        }
        let pruned = try dbQueue.write { db in try SyncDeferredApplies.prune(db: db) }
        #expect(pruned == 0)
        #expect(try dbQueue.read { db in try SyncDeferredApplies.count(db: db) } == 1)
    }

    // MARK: - The scenario

    @Test("A highlight that arrives before its book is applied once the book lands")
    func outOfOrderArrivalRecovers() throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        let record = highlightRecord(bookID: book.id)

        // Batch one: the highlight, with no book yet. Inserting it directly
        // would throw on the foreign key and the record would be gone.
        #expect(throws: (any Error).self) {
            try dbQueue.write { db in
                try #require(Highlight.from(ckRecord: record)).insert(db)
            }
        }
        try dbQueue.write { db in try SyncDeferredApplies.park(db: db, record: record) }

        // Batch two: the book arrives.
        try dbQueue.write { db in try book.insert(db) }

        let parked = try dbQueue.read { db in try SyncDeferredApplies.pending(db: db) }
        let restored = try #require(parked.first)
        #expect(try dbQueue.read { db in
            try SyncDeferredApplies.parentsExist(db: db, record: restored)
        })

        try dbQueue.write { db in
            try #require(Highlight.from(ckRecord: restored)).insert(db)
            try SyncDeferredApplies.remove(db: db, type: restored.recordType,
                                           recordName: restored.recordID.recordName)
        }

        let stored = try dbQueue.read { db in try Highlight.fetchAll(db) }
        #expect(stored.count == 1)
        #expect(stored.first?.bookID == book.id)
        #expect(try dbQueue.read { db in try SyncDeferredApplies.count(db: db) } == 0)
    }
}
