import CloudKit
import Foundation
import GRDB
import Testing

@testable import Fathom

/// Migration v35's trigger rules, the full-record metadata cache, and the
/// deferred-apply fixes that go with them. Everything here runs through the
/// real migration chain and the real triggers.
struct SyncApplyTriggerTests {

    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

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

    nonisolated private func clearQueue(_ dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM cloudkit_pending_changes") }
    }

    nonisolated private func insertBook(_ dbQueue: DatabaseQueue) throws -> Book {
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try dbQueue.write { db in try book.insert(db) }
        return book
    }

    // MARK: - Device-only book columns

    @Test("Changing a device-only book column queues nothing")
    func localOnlyBookColumnIsNotPushed() throws {
        let dbQueue = try makeMigratedQueue()
        var book = try insertBook(dbQueue)
        try clearQueue(dbQueue)

        book.preprocessingStatus = .completed
        book.aiAnalysisProgress = 0.5
        try dbQueue.write { db in try book.update(db) }

        #expect(try queued(dbQueue).isEmpty)
    }

    @Test("Changing a synced book column queues the book")
    func syncedBookColumnIsPushed() throws {
        let dbQueue = try makeMigratedQueue()
        var book = try insertBook(dbQueue)
        try clearQueue(dbQueue)

        book.title = "Pale Blue Dot"
        try dbQueue.write { db in try book.update(db) }

        #expect(try queued(dbQueue).map(\.recordType) == [CKRecordType.book])
    }

    // MARK: - Writes made by sync

    @Test("A write inside the apply context queues nothing and keeps modifiedAt")
    func applyContextSuppressesTriggers() throws {
        let dbQueue = try makeMigratedQueue()
        var book = try insertBook(dbQueue)
        try clearQueue(dbQueue)

        let remoteModifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        book.title = "Remote title"
        book.modifiedAt = remoteModifiedAt
        try dbQueue.write { db in
            try SyncApplyContext.perform(db) { try book.update(db) }
        }

        #expect(try queued(dbQueue).isEmpty)
        let stored = try #require(try dbQueue.read { db in try Book.fetchOne(db, key: book.id) })
        #expect(abs(stored.modifiedAt.timeIntervalSince(remoteModifiedAt)) < 0.01,
                "the other device's modifiedAt must not be restamped with this device's clock")
    }

    @Test("Apply contexts nest, and local writes queue again once they close")
    func applyContextNests() throws {
        let dbQueue = try makeMigratedQueue()
        var book = try insertBook(dbQueue)
        try clearQueue(dbQueue)

        try dbQueue.write { db in
            try SyncApplyContext.perform(db) {
                try SyncApplyContext.perform(db) {
                    book.title = "Inner"
                    try book.update(db)
                }
                // Still inside the outer scope.
                book.title = "Outer"
                try book.update(db)
            }
        }
        #expect(try queued(dbQueue).isEmpty)

        book.title = "Local"
        try dbQueue.write { db in try book.update(db) }
        #expect(try queued(dbQueue).count == 1)
    }

    @Test("A pulled record does not wipe a local edit queued for the same row")
    func applyKeepsUnrelatedQueueRows() throws {
        // The old engine let the trigger fire during apply and then deleted the
        // queue row by record ID — taking a genuine local edit with it.
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)
        try clearQueue(dbQueue)

        let highlight = Highlight(id: UUID(), bookID: book.id, locatorJSON: "{}",
                                  text: "a line", createdAt: Date(), color: .yellow)
        try dbQueue.write { db in try highlight.insert(db) }   // local edit, queued

        let remoteBook = book.toCKRecord(zoneID: zoneID)
        remoteBook["title"] = "Renamed elsewhere"
        try dbQueue.write { db in
            let parsed = try #require(CKRecordName.parse(remoteBook.recordID.recordName))
            _ = try SyncEngine.applyRow(db: db, record: remoteBook, type: parsed.type,
                                        localID: parsed.localID, cacheSystemFields: true)
        }

        #expect(try queued(dbQueue).map(\.recordType) == [CKRecordType.highlight])
    }

    // MARK: - Deletes

    @Test("Deleting a book queues deletes for its annotations too")
    func cascadeQueuesChildDeletes() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)
        let highlight = Highlight(id: UUID(), bookID: book.id, locatorJSON: "{}",
                                  text: "a line", createdAt: Date(), color: .yellow)
        try dbQueue.write { db in try highlight.insert(db) }
        try clearQueue(dbQueue)

        try dbQueue.write { db in _ = try book.delete(db) }

        let rows = try queued(dbQueue)
        #expect(rows.contains { $0.recordType == CKRecordType.highlight && $0.operation == "delete" })
        #expect(rows.contains { $0.recordType == CKRecordType.book && $0.operation == "delete" })
    }

    @Test("A book deleted by sync queues nothing for its cascade")
    func remoteCascadeQueuesNothing() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)
        let highlight = Highlight(id: UUID(), bookID: book.id, locatorJSON: "{}",
                                  text: "a line", createdAt: Date(), color: .yellow)
        try dbQueue.write { db in try highlight.insert(db) }
        try clearQueue(dbQueue)

        try dbQueue.write { db in
            try SyncApplyContext.perform(db) { _ = try book.delete(db) }
        }

        #expect(try queued(dbQueue).isEmpty)
        #expect(try dbQueue.read { db in try Highlight.fetchCount(db) } == 0)
    }

    // MARK: - Metadata cache

    @Test("The metadata cache keeps field values, not just system fields")
    func metadataKeepsValues() throws {
        // CloudKit derives a conflict's ancestor from the record an upload was
        // built on. A system-fields-only cache produced value-less ancestors,
        // and every conflict then discarded the local edit.
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        let record = book.toCKRecord(zoneID: zoneID)

        try dbQueue.write { db in try SyncRecordMetadata.save(db: db, record: record) }
        let cached = try #require(try dbQueue.read { db in
            try SyncRecordMetadata.lastKnownRecord(db: db, type: CKRecordType.book,
                                                   recordName: record.recordID.recordName)
        })

        #expect(cached["title"] as? String == "Cosmos")
        #expect(cached["author"] as? String == "Sagan")
    }

    // MARK: - Deferred applies

    @Test("Re-parking a record keeps its original deferral time")
    func reparkKeepsDeferredAt() throws {
        // Resetting the time on every attempt meant nothing ever aged out.
        let dbQueue = try makeMigratedQueue()
        let highlight = Highlight(id: UUID(), bookID: UUID(), locatorJSON: "{}",
                                  text: "a line", createdAt: Date(), color: .yellow)
        let record = highlight.toCKRecord(zoneID: zoneID)
        let longAgo = Date().addingTimeInterval(-(SyncDeferredApplies.maximumAge + 60))

        try dbQueue.write { db in
            try SyncDeferredApplies.park(db: db, record: record)
            try db.execute(sql: "UPDATE cloudkit_deferred_applies SET deferredAt = ?",
                           arguments: [longAgo])
            try SyncDeferredApplies.park(db: db, record: record)
        }

        let pruned = try dbQueue.write { db in try SyncDeferredApplies.prune(db: db) }
        #expect(pruned == 1)
    }

    @Test("Applying a record directly removes an older parked copy of it")
    func directApplyClearsStaleParkedCopy() throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        let highlight = Highlight(id: UUID(), bookID: book.id, locatorJSON: "{}",
                                  text: "a line", createdAt: Date(), color: .yellow)
        let stale = highlight.toCKRecord(zoneID: zoneID)
        try dbQueue.write { db in try SyncDeferredApplies.park(db: db, record: stale) }

        try dbQueue.write { db in try book.insert(db) }
        let newer = highlight.toCKRecord(zoneID: zoneID)
        newer["color"] = HighlightColor.blue.rawValue
        try dbQueue.write { db in
            let parsed = try #require(CKRecordName.parse(newer.recordID.recordName))
            let applied = try SyncEngine.applyRow(db: db, record: newer, type: parsed.type,
                                                  localID: parsed.localID, cacheSystemFields: true)
            #expect(applied)
        }

        #expect(try dbQueue.read { db in try SyncDeferredApplies.count(db: db) } == 0)
    }

    @Test("A record that will not decode is parked, not reported as applied")
    func undecodableRecordIsParked() throws {
        let dbQueue = try makeMigratedQueue()
        let book = try insertBook(dbQueue)
        let highlight = Highlight(id: UUID(), bookID: book.id, locatorJSON: "{}",
                                  text: "a line", createdAt: Date(), color: .yellow)
        let record = highlight.toCKRecord(zoneID: zoneID)
        record["text"] = nil   // required field missing

        try dbQueue.write { db in
            let parsed = try #require(CKRecordName.parse(record.recordID.recordName))
            let applied = try SyncEngine.applyRow(db: db, record: record, type: parsed.type,
                                                  localID: parsed.localID, cacheSystemFields: true)
            #expect(!applied)
        }

        #expect(try dbQueue.read { db in try SyncDeferredApplies.count(db: db) } == 1)
        #expect(try dbQueue.read { db in try Highlight.fetchCount(db) } == 0)
    }
}
