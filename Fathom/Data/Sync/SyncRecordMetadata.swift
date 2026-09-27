import CloudKit
import Foundation
import GRDB

/// Caches the last version of every record the server has acknowledged —
/// system fields (change tag, record ID, zone, timestamps) **and values**.
///
/// The change tag lets a save say "this is an update to what I have" rather
/// than a blind overwrite; without it every save after the first conflicts.
///
/// The values are what make the three-way merge work. This table used to hold
/// `encodeSystemFields` output only, and records to push were rebuilt on top
/// of it. CloudKit derives a conflict's `ancestorRecord` from the record the
/// upload was built on, so every ancestor arrived with metadata and no values:
/// each differing field read as "changed on both sides", the server won, and a
/// local edit or a local clear was discarded on every conflict. Archiving the
/// full record with `encode(with:)` gives CloudKit — and `SyncMerge` — a real
/// common ancestor.
///
/// Rows written by older builds hold system fields only. They still decode and
/// still carry a valid tag; they are replaced with full records the next time
/// the record is fetched or saved.
///
/// The column is still named `systemFields` — renaming it buys nothing.
nonisolated enum SyncRecordMetadata {

    // MARK: - Read

    /// The last record the server acknowledged for this ID. Values are
    /// present for rows written by this build; callers overwrite every field
    /// they own before saving.
    static func lastKnownRecord(db: Database,
                                type: CKRecord.RecordType,
                                recordName: String) throws -> CKRecord? {
        guard let data = try Data.fetchOne(db, sql: """
            SELECT systemFields
            FROM   cloudkit_record_metadata
            WHERE  recordType = ? AND recordID = ?
            """, arguments: [type, recordName]) else { return nil }

        return decode(data)
    }

    static func decode(_ data: Data) -> CKRecord? {
        do {
            let coder = try NSKeyedUnarchiver(forReadingFrom: data)
            coder.requiresSecureCoding = true
            let record = CKRecord(coder: coder)
            coder.finishDecoding()
            return record
        } catch {
            // A metadata row we cannot read is recoverable: the record is
            // pushed without a tag, conflicts once, and the merge resolves it.
            AppLogger.log(tag: "SyncRecordMetadata", "Undecodable cached record: \(error)")
            return nil
        }
    }

    // MARK: - Write

    /// Records the server's current version of a record. Call for every record
    /// the server hands back — both saves we made and changes we fetched.
    static func save(db: Database, record: CKRecord) throws {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        // `encode(with:)`, not `encodeSystemFields(with:)`: the values are the
        // ancestor for the next conflict. See the type comment.
        record.encode(with: coder)
        coder.finishEncoding()

        try db.execute(sql: """
            INSERT INTO cloudkit_record_metadata
                (recordType, recordID, systemFields, updatedAt)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(recordType, recordID) DO UPDATE SET
                systemFields = excluded.systemFields,
                updatedAt    = excluded.updatedAt
            """, arguments: [record.recordType,
                             record.recordID.recordName,
                             coder.encodedData,
                             Date()])
    }

    // MARK: - Delete

    static func delete(db: Database, type: CKRecord.RecordType, recordName: String) throws {
        try db.execute(sql: """
            DELETE FROM cloudkit_record_metadata
            WHERE recordType = ? AND recordID = ?
            """, arguments: [type, recordName])
    }

    /// Drops every cached record. Used when the account changes or the zone is
    /// recreated — the tags describe records in a zone that no longer exists,
    /// and reusing them would make every first save fail.
    static func deleteAll(db: Database) throws {
        try db.execute(sql: "DELETE FROM cloudkit_record_metadata")
    }

    /// Whether the server has ever acknowledged this record.
    static func exists(db: Database, type: CKRecord.RecordType, recordName: String) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM cloudkit_record_metadata
                           WHERE recordType = ? AND recordID = ?)
            """, arguments: [type, recordName]) ?? false
    }
}
