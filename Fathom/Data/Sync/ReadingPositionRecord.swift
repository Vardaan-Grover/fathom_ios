import CloudKit
import Foundation

/// The CloudKit shape of a reading position.
///
/// Reading state lives in a file rather than a table, so it has no
/// `CloudKitSyncable` conformance to hold its field names in one place. They
/// were spelled out by hand on the push side and again on the pull side, with
/// nothing but matching string literals connecting the two — rename one and
/// position sync stops working silently, with no test to notice and no error in
/// the log. Both sides go through here now, and `ReadingPositionRecordTests`
/// round-trips it.
///
/// The field names are also the ones deployed in `CloudKit/schema.ckdb`, and
/// CloudKit's production schema is additive-only: a rename here means a new
/// field, not a changed one.
nonisolated enum ReadingPositionRecord {

    static func write(_ state: ReadingState, bookID: UUID, into record: CKRecord) {
        record["bookID"] = bookID.uuidString
        record["locatorJSON"] = state.locatorJSON
        record["savedAt"] = state.savedAt
        record["furthestProgression"] = state.furthestProgression
    }

    /// Reads a position back, or nil if the record cannot supply one.
    ///
    /// `savedAt` is required rather than defaulted: it is what decides which of
    /// two positions wins, and a record missing it would arrive stamped with
    /// the distant past and lose every conflict forever. `furthestProgression`
    /// does default — it merges by `max`, so a missing value contributes
    /// nothing and cannot pull the mark down.
    static func read(_ record: CKRecord) -> (bookID: UUID, state: ReadingState)? {
        guard
            let bookIDString = record["bookID"] as? String,
            let bookID = UUID(uuidString: bookIDString),
            let locatorJSON = record["locatorJSON"] as? String,
            let savedAt = record["savedAt"] as? Date
        else { return nil }

        return (bookID, ReadingState(
            locatorJSON: locatorJSON,
            savedAt: savedAt,
            furthestProgression: record["furthestProgression"] as? Double ?? 0
        ))
    }
}
