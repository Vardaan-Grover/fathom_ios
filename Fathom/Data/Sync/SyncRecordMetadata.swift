import CloudKit
import Foundation
import GRDB

/// Caches the CloudKit *system fields* of every record the server has
/// acknowledged — change tag, record ID, zone, creation and modification
/// metadata. Never user data: `encodeSystemFields` deliberately omits the
/// record's values, so this table stays small regardless of library size.
///
/// The change tag is the point. Saving a record that carries the tag of the
/// version it was derived from lets CloudKit distinguish "this is an update to
/// what I have" from "this is a blind overwrite". Without it every save after
/// the first is a conflict, which is why the previous engine forced
/// `.changedKeys` and, in doing so, overwrote server state it had never read.
nonisolated enum SyncRecordMetadata {

    // MARK: - Read

    /// The last record the server acknowledged for this ID, with system fields
    /// only — values must be re-applied by the caller before saving.
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
            AppLogger.log(tag: "SyncRecordMetadata", "Undecodable system fields: \(error)")
            return nil
        }
    }

    // MARK: - Write

    /// Records the server's current version of a record. Call for every record
    /// the server hands back — both saves we made and changes we fetched.
    static func save(db: Database, record: CKRecord) throws {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
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

    /// Drops every cached tag. Used when the account changes or the zone is
    /// recreated — the tags describe records in a zone that no longer exists,
    /// and reusing them would make every first save fail.
    static func deleteAll(db: Database) throws {
        try db.execute(sql: "DELETE FROM cloudkit_record_metadata")
    }
}
