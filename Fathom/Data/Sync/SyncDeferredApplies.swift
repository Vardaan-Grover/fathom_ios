import CloudKit
import Foundation
import GRDB

/// Holds fetched records whose parent has not arrived yet, so they can be
/// applied once it does.
///
/// Six synced tables carry a NOT NULL foreign key to `books`, and CloudKit
/// makes no promise about the order records arrive in. Sorting each batch
/// parents-first covers the ordinary case, but a highlight can still arrive in
/// an earlier batch than the book it belongs to. Inserting it then throws, and
/// without somewhere to park it the record is dropped for good — CloudKit does
/// not redeliver it, so the annotation never appears on that device.
///
/// A device that already holds every book cannot hit this. A clean install can,
/// on its very first sync, which makes it everyone's first impression.
nonisolated enum SyncDeferredApplies {

    /// How long a record waits for a parent that may never come. A parent can
    /// be permanently absent — the book was deleted on the other device after
    /// the child was written — and without a bound those rows accumulate
    /// forever.
    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - Park

    static func park(db: Database, record: CKRecord) throws {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        // The whole record, values included — unlike SyncRecordMetadata, which
        // deliberately stores system fields only.
        record.encode(with: coder)
        coder.finishEncoding()

        // A re-park replaces the record (a newer version supersedes an older
        // one) but keeps the original `deferredAt`. Resetting it on every
        // attempt — which is what happened when each drain re-parked what it
        // could not apply — meant nothing ever aged past `maximumAge`, so the
        // prune never ran and orphans accumulated without bound.
        try db.execute(sql: """
            INSERT INTO cloudkit_deferred_applies
                (recordType, recordID, record, deferredAt)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(recordType, recordID) DO UPDATE SET
                record = excluded.record
            """, arguments: [record.recordType,
                             record.recordID.recordName,
                             coder.encodedData,
                             Date()])
    }

    // MARK: - Read

    /// Parked records, oldest first. Decoding failures are dropped rather than
    /// retried forever.
    static func pending(db: Database) throws -> [CKRecord] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT recordType, recordID, record FROM cloudkit_deferred_applies
            ORDER BY deferredAt ASC
            """)

        var records: [CKRecord] = []
        for row in rows {
            guard let data: Data = row["record"] else { continue }
            if let record = decode(data) {
                records.append(record)
            } else {
                let type: String = row["recordType"] ?? ""
                let name: String = row["recordID"] ?? ""
                AppLogger.log(tag: "SyncDeferred", "Undecodable parked record \(type)/\(name) — dropping")
                try? remove(db: db, type: type, recordName: name)
            }
        }
        return records
    }

    static func count(db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cloudkit_deferred_applies") ?? 0
    }

    private static func decode(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    // MARK: - Remove

    static func remove(db: Database, type: CKRecord.RecordType, recordName: String) throws {
        try db.execute(sql: """
            DELETE FROM cloudkit_deferred_applies
            WHERE recordType = ? AND recordID = ?
            """, arguments: [type, recordName])
    }

    /// Drops records that have waited past `maximumAge`. Their parent is not
    /// coming — most likely deleted on the other device.
    @discardableResult
    static func prune(db: Database, now: Date = Date()) throws -> Int {
        let cutoff = now.addingTimeInterval(-maximumAge)
        try db.execute(sql: "DELETE FROM cloudkit_deferred_applies WHERE deferredAt < ?",
                       arguments: [cutoff])
        return db.changesCount
    }

    static func removeAll(db: Database) throws {
        try db.execute(sql: "DELETE FROM cloudkit_deferred_applies")
    }

    // MARK: - Parent checks

    /// Whether a record is parked — used to drop a stale parked copy once a
    /// newer version of the same record has been applied directly.
    static func contains(db: Database, type: CKRecord.RecordType, recordName: String) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM cloudkit_deferred_applies
                           WHERE recordType = ? AND recordID = ?)
            """, arguments: [type, recordName]) ?? false
    }

    /// Whether every row this record points at exists locally.
    ///
    /// Nullability is not the question. `saved_words.bookID` is nullable with
    /// `ON DELETE SET NULL`, which permits *NULL* — it does not permit a
    /// non-NULL value pointing at a row that is not there. Any foreign key can
    /// fail that way, so every reference is checked, and a nil id is treated as
    /// satisfied rather than skipped.
    static func parentsExist(db: Database, record: CKRecord) throws -> Bool {
        switch record.recordType {
        case CKRecordType.bookCompletion,
             CKRecordType.highlight,
             CKRecordType.note,
             CKRecordType.bookmark,
             CKRecordType.readingActivity,
             CKRecordType.savedWord:
            // A nil bookID is fine — a word can be saved outside any book, and
            // saved_words.bookID is nullable for exactly that. What is not fine
            // is a non-nil id pointing at a book that is not here: a nullable
            // column still rejects a dangling reference, which is what dropped
            // 20 saved words on the first clean install.
            guard let bookID = uuid(record["bookID"]) else { return true }
            return try Book.exists(db, key: bookID)

        case CKRecordType.bookCategoryMembership:
            guard let bookID = uuid(record["bookID"]),
                  let categoryID = uuid(record["categoryID"]) else { return true }
            return try Book.exists(db, key: bookID)
                && BookCategory.exists(db, key: categoryID)

        default:
            return true
        }
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }
}
