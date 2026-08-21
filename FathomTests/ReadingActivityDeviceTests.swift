import Foundation
import GRDB
import Testing

@testable import Fathom

/// Reading time is additive across devices. These cover the per-device
/// partition that makes summing correct — see §3.4 of
/// docs/sync-conflict-policy.md.
struct ReadingActivityDeviceTests {

    nonisolated private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    nonisolated private func insertBook(_ dbQueue: DatabaseQueue) throws -> UUID {
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try dbQueue.write { db in try book.insert(db) }
        return book.id
    }

    nonisolated private func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    nonisolated private func totalDuration(_ dbQueue: DatabaseQueue, date: String) throws -> TimeInterval {
        try dbQueue.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(duration), 0) FROM readingActivity WHERE date = ?",
                arguments: [date]) ?? 0
        }
    }

    // MARK: - Schema

    @Test("The uniqueness constraint includes the device")
    func uniqueIndexIsPerDevice() throws {
        let dbQueue = try makeMigratedQueue()
        let indexes = try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'readingActivity'")
        }
        #expect(indexes.contains("idx_readingActivity_book_date_device"))
        // The old two-column constraint is what forced two devices to share a
        // row; it must be gone, not merely supplemented.
        #expect(!indexes.contains("idx_readingActivity_book_date"))
    }

    // MARK: - The bug

    @Test("Two devices reading the same day sum instead of taking the larger")
    func twoDevicesSum() throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = try insertBook(dbQueue)
        let day = "2026-08-21"

        // 20 minutes on one device, 15 on another.
        try dbQueue.write { db in
            try ReadingActivity(id: UUID(), bookID: bookID, date: day,
                                duration: 1200, createdAt: Date(),
                                deviceID: "device-iphone").insert(db)
            try ReadingActivity(id: UUID(), bookID: bookID, date: day,
                                duration: 900, createdAt: Date(),
                                deviceID: "device-ipad").insert(db)
        }

        // The old max(duration) merge recorded 1200. The real answer is 2100.
        #expect(try totalDuration(dbQueue, date: day) == 2100)
    }

    @Test("A day's rows are one per device, not one per book")
    func rowsArePerDevice() throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = try insertBook(dbQueue)
        let day = "2026-08-21"

        try dbQueue.write { db in
            try ReadingActivity(id: UUID(), bookID: bookID, date: day,
                                duration: 60, createdAt: Date(),
                                deviceID: "a").insert(db)
            try ReadingActivity(id: UUID(), bookID: bookID, date: day,
                                duration: 60, createdAt: Date(),
                                deviceID: "b").insert(db)
        }

        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM readingActivity") ?? 0
        }
        #expect(count == 2)
    }

    @Test("The same device cannot hold two rows for one book and day")
    func sameDeviceRowIsStillUnique() throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = try insertBook(dbQueue)
        let day = "2026-08-21"

        try dbQueue.write { db in
            try ReadingActivity(id: UUID(), bookID: bookID, date: day,
                                duration: 60, createdAt: Date(),
                                deviceID: "a").insert(db)
        }

        #expect(throws: (any Error).self) {
            try dbQueue.write { db in
                try ReadingActivity(id: UUID(), bookID: bookID, date: day,
                                    duration: 60, createdAt: Date(),
                                    deviceID: "a").insert(db)
            }
        }
    }

    // MARK: - Write path

    @Test("Logging a session accumulates into this device's row only")
    func loggingScopesToThisDevice() async throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = try insertBook(dbQueue)
        let repo = BookRepositorySQLite(dbQueue: dbQueue)

        let day = today()

        // A row that arrived from another device.
        try await dbQueue.write { db in
            try ReadingActivity(id: UUID(), bookID: bookID, date: day,
                                duration: 900, createdAt: Date(),
                                deviceID: "some-other-device").insert(db)
        }

        await repo.logReadingSession(for: bookID, duration: 300)

        // The other device's row must be untouched — adding to it would
        // double-count time it already reported.
        let otherRow = try await dbQueue.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT duration FROM readingActivity WHERE deviceID = ?",
                arguments: ["some-other-device"])
        }
        #expect(otherRow == 900)
        #expect(try totalDuration(dbQueue, date: day) == 1200)
    }

    @Test("Repeated sessions on the same day accumulate instead of being dropped")
    func repeatedSessionsAccumulate() async throws {
        let dbQueue = try makeMigratedQueue()
        let bookID = try insertBook(dbQueue)
        let repo = BookRepositorySQLite(dbQueue: dbQueue)

        await repo.logReadingSession(for: bookID, duration: 120)
        await repo.logReadingSession(for: bookID, duration: 180)

        // Regression guard. The previous implementation looked the row up with
        // `WHERE bookID = ?` bound to `bookID.uuidString`, but GRDB stores UUID
        // as a 16-byte blob, so the lookup never matched. Every session after
        // the first each day hit the unique index, threw, and was swallowed by
        // the repository's catch — the time was silently lost.
        let rows = try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM readingActivity") ?? 0
        }
        #expect(rows == 1)
        #expect(try totalDuration(dbQueue, date: today()) == 300)
    }

    // MARK: - Sync round trip

    @Test("deviceID survives the CloudKit round trip")
    func deviceIDRoundTrips() throws {
        let zoneID = CKRecordZoneIDForTesting
        let activity = ReadingActivity(
            id: UUID(), bookID: UUID(), date: "2026-08-21",
            duration: 1500, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            deviceID: "device-ipad")

        let decoded = try #require(
            ReadingActivity.from(ckRecord: activity.toCKRecord(zoneID: zoneID)))
        #expect(decoded.deviceID == "device-ipad")
        #expect(decoded.duration == 1500)
    }
}

import CloudKit
private let CKRecordZoneIDForTesting = CKRecordZone.ID(
    zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
