import CloudKit
import Foundation
import Testing

@testable import Fathom

/// Covers the three-way merge that resolves `serverRecordChanged` conflicts.
/// See `docs/sync-conflict-policy.md`.
struct SyncMergeTests {

    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    private func bookRecord(_ localID: String = UUID().uuidString) -> CKRecord {
        CKRecord(recordType: CKRecordType.book,
                 recordID: CKRecordName.id(type: CKRecordType.book,
                                           localID: localID,
                                           zoneID: zoneID))
    }

    // MARK: - The bug this whole migration exists to fix

    @Test("A field cleared on this device propagates instead of being resurrected")
    func clearedFieldPropagates() {
        let id = UUID().uuidString

        // Ancestor: the book had a rating of 4.
        let ancestor = bookRecord(id)
        ancestor["rating"] = 4
        ancestor["reflection"] = "Good."

        // This device cleared the rating. The server has not touched it.
        let client = bookRecord(id)
        client["rating"] = nil
        client["reflection"] = "Good."

        let server = bookRecord(id)
        server["rating"] = 4
        server["reflection"] = "Good."

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)

        // The old engine coalesced nil to the existing value, which made a
        // clear unrepresentable and silently restored the 4.
        #expect(merged["rating"] == nil)
        #expect(merged["reflection"] as? String == "Good.")
    }

    @Test("An edit on this device wins when the server did not touch the field")
    func clientOnlyEditWins() {
        let id = UUID().uuidString
        let ancestor = bookRecord(id); ancestor["reflection"] = "First pass."
        let client = bookRecord(id);   client["reflection"] = "Second pass."
        let server = bookRecord(id);   server["reflection"] = "First pass."

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
        #expect(merged["reflection"] as? String == "Second pass.")
    }

    @Test("An edit on the other device survives an unrelated local edit")
    func concurrentEditsToDifferentFieldsBothSurvive() {
        let id = UUID().uuidString
        let ancestor = bookRecord(id)
        ancestor["rating"] = 3
        ancestor["reflection"] = "Original."

        // This device changed the rating only.
        let client = bookRecord(id)
        client["rating"] = 5
        client["reflection"] = "Original."

        // The other device changed the reflection only.
        let server = bookRecord(id)
        server["rating"] = 3
        server["reflection"] = "Rewritten elsewhere."

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)

        // Whole-record last-writer-wins would have dropped one of these.
        #expect(merged["rating"] as? Int == 5)
        #expect(merged["reflection"] as? String == "Rewritten elsewhere.")
    }

    // MARK: - Contended fields

    @Test("A genuine concurrent edit to one field resolves deterministically")
    func contendedFieldPrefersServer() {
        let id = UUID().uuidString
        let ancestor = bookRecord(id); ancestor["reflection"] = "Original."
        let client = bookRecord(id);   client["reflection"] = "Mine."
        let server = bookRecord(id);   server["reflection"] = "Theirs."

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)

        // Either answer loses an edit; what matters is that every device makes
        // the *same* choice, so the two stop overwriting each other.
        #expect(merged["reflection"] as? String == "Theirs.")
    }

    @Test("High-water marks take the later value regardless of which side it is on")
    func maxWinsTakesTheLater() {
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late  = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID().uuidString

        let ancestor = bookRecord(id); ancestor["lastReadAt"] = early
        let client = bookRecord(id);   client["lastReadAt"] = late
        let server = bookRecord(id);   server["lastReadAt"] = Date(timeIntervalSince1970: 1_750_000_000)

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
        #expect(merged["lastReadAt"] as? Date == late)
    }

    @Test("A delete beats a concurrent edit and is never undone by merge")
    func tombstoneBeatsEdit() {
        let id = UUID().uuidString
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let recordID = CKRecordName.id(type: CKRecordType.highlight,
                                       localID: id,
                                       zoneID: zoneID)
        let ancestor = CKRecord(recordType: CKRecordType.highlight, recordID: recordID)
        ancestor["color"] = "yellow"

        // This device recoloured the highlight.
        let client = CKRecord(recordType: CKRecordType.highlight, recordID: recordID)
        client["color"] = "blue"

        // The other device deleted it.
        let server = CKRecord(recordType: CKRecordType.highlight, recordID: recordID)
        server["color"] = "yellow"
        server["deletedAt"] = deletedAt

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
        #expect(merged["deletedAt"] as? Date == deletedAt)
    }

    @Test("A delete made on this device is not resurrected by the server's copy")
    func localTombstoneSurvives() {
        let id = UUID().uuidString
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let recordID = CKRecordName.id(type: CKRecordType.bookmark,
                                       localID: id,
                                       zoneID: zoneID)

        let ancestor = CKRecord(recordType: CKRecordType.bookmark, recordID: recordID)
        let client = CKRecord(recordType: CKRecordType.bookmark, recordID: recordID)
        client["deletedAt"] = deletedAt
        let server = CKRecord(recordType: CKRecordType.bookmark, recordID: recordID)

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
        #expect(merged["deletedAt"] as? Date == deletedAt)
    }

    // MARK: - Agreement is not conflict

    @Test("Identical values are not treated as a conflict, whatever the ancestor says")
    func agreementIsNotConflict() {
        let id = UUID().uuidString

        // CloudKit's ancestor for a record this device never fetched carries
        // system fields but no user values. Without a short-circuit that makes
        // every field read as contended — and every immutable field gets
        // reported as diverged, which is what the first real run logged for
        // all 250 records while both sides held identical data.
        let ancestor = bookRecord(id)          // no user fields, as CloudKit sends
        let client = bookRecord(id)
        client["title"] = "Cosmos"
        client["rating"] = 4
        let server = bookRecord(id)
        server["title"] = "Cosmos"
        server["rating"] = 4

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
        #expect(merged["title"] as? String == "Cosmos")
        #expect(merged["rating"] as? Int == 4)
    }

    @Test("An empty ancestor still lets a one-sided value through")
    func emptyAncestorKeepsClientOnlyValue() {
        let id = UUID().uuidString
        let ancestor = bookRecord(id)
        let client = bookRecord(id); client["reflection"] = "Only mine."
        let server = bookRecord(id)

        // Server has nothing for this field, so there is no contention to
        // resolve and the value must survive.
        let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
        #expect(merged["reflection"] as? String == "Only mine.")
    }

    // MARK: - No ancestor
    //
    // CloudKit omits the ancestor whenever the client record was never derived
    // from a server version — the "record to insert already exists" case, which
    // is what a device with an empty metadata cache and a populated zone
    // produces. The first real run against CloudKit hit it on all 250 records.

    @Test("A field only this device has survives when there is no ancestor")
    func missingAncestorKeepsClientOnlyFields() {
        let id = UUID().uuidString
        let client = bookRecord(id); client["rating"] = 5
        let server = bookRecord(id); server["reflection"] = "Theirs."

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: nil)
        #expect(merged["reflection"] as? String == "Theirs.")
        #expect(merged["rating"] as? Int == 5)
    }

    @Test("Without an ancestor the newer record wins a contended field")
    func missingAncestorPrefersNewer() {
        let id = UUID().uuidString
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)

        // This device edited more recently but never pushed, so there is no
        // ancestor. Preferring the server here would silently discard the
        // newer local edit — the exact data loss the policy exists to prevent.
        let client = bookRecord(id)
        client["reflection"] = "Mine, newer."
        client["modifiedAt"] = newer

        let server = bookRecord(id)
        server["reflection"] = "Theirs, older."
        server["modifiedAt"] = older

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: nil)
        #expect(merged["reflection"] as? String == "Mine, newer.")
    }

    @Test("Without an ancestor an older local edit does not overwrite the server")
    func missingAncestorKeepsServerWhenOlder() {
        let id = UUID().uuidString
        let client = bookRecord(id)
        client["reflection"] = "Mine, older."
        client["modifiedAt"] = Date(timeIntervalSince1970: 1_700_000_000)

        let server = bookRecord(id)
        server["reflection"] = "Theirs, newer."
        server["modifiedAt"] = Date(timeIntervalSince1970: 1_800_000_000)

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: nil)
        #expect(merged["reflection"] as? String == "Theirs, newer.")
    }

    @Test("Immutable fields are taken from the server without being called divergent")
    func missingAncestorDoesNotReportImmutableDivergence() {
        let id = UUID().uuidString
        // Both sides carry the same import metadata. With no ancestor the old
        // code read every one of these as contended and logged an immutable
        // divergence for each — 51 Book fields per pass in the real run.
        let client = bookRecord(id); client["title"] = "Cosmos"
        let server = bookRecord(id); server["title"] = "Cosmos"

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: nil)
        #expect(merged["title"] as? String == "Cosmos")
    }

    @Test("A tombstone still wins when there is no ancestor")
    func missingAncestorTombstoneStillWins() {
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let recordID = CKRecordName.id(type: CKRecordType.highlight,
                                       localID: UUID().uuidString, zoneID: zoneID)
        let client = CKRecord(recordType: CKRecordType.highlight, recordID: recordID)
        client["color"] = "blue"
        // The client is newer, but a delete is final regardless.
        client["modifiedAt"] = Date(timeIntervalSince1970: 1_900_000_000)

        let server = CKRecord(recordType: CKRecordType.highlight, recordID: recordID)
        server["deletedAt"] = deletedAt
        server["modifiedAt"] = Date(timeIntervalSince1970: 1_700_000_000)

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: nil)
        #expect(merged["deletedAt"] as? Date == deletedAt)
    }

    @Test("A high-water mark still takes the larger value with no ancestor")
    func missingAncestorMaxWinsStillApplies() {
        let id = UUID().uuidString
        let late = Date(timeIntervalSince1970: 1_900_000_000)

        // The client is older overall, so lastWriterWins would drop this — but
        // lastReadAt only ever moves forward.
        let client = bookRecord(id)
        client["lastReadAt"] = late
        client["modifiedAt"] = Date(timeIntervalSince1970: 1_700_000_000)

        let server = bookRecord(id)
        server["lastReadAt"] = Date(timeIntervalSince1970: 1_750_000_000)
        server["modifiedAt"] = Date(timeIntervalSince1970: 1_800_000_000)

        let merged = SyncMerge.resolve(client: client, server: server, ancestor: nil)
        #expect(merged["lastReadAt"] as? Date == late)
    }
}

/// Record naming — the collision fix.
struct CKRecordNameTests {

    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    @Test("A book and its reading position no longer claim the same record name")
    func bookAndPositionDoNotCollide() {
        // A record name identifies a record uniquely within a zone across all
        // types. Using the bare book UUID for both meant the two could not
        // coexist — the bug that had never surfaced because sync never ran.
        let bookID = UUID().uuidString
        let book = CKRecordName.make(type: CKRecordType.book, localID: bookID)
        let position = CKRecordName.make(type: CKRecordType.readingPosition, localID: bookID)

        #expect(book != position)
    }

    @Test("Record names round-trip to their type and local identifier")
    func namesRoundTrip() {
        let localID = UUID().uuidString
        let name = CKRecordName.make(type: CKRecordType.highlight, localID: localID)
        let parsed = CKRecordName.parse(name)

        #expect(parsed?.type == CKRecordType.highlight)
        #expect(parsed?.localID == localID)
    }

    @Test("Names from an unknown record type are rejected rather than half-parsed")
    func unknownTypesRejected() {
        #expect(CKRecordName.parse("AIConversation.\(UUID().uuidString)") == nil)
        #expect(CKRecordName.parse(UUID().uuidString) == nil)
        #expect(CKRecordName.parse("") == nil)
    }

    @Test("Record names use only characters CloudKit accepts")
    func namesUseLegalCharacters() {
        let membership = CKRecordName.membershipLocalID(bookID: UUID(), categoryID: UUID())
        let name = CKRecordName.make(type: CKRecordType.bookCategoryMembership,
                                     localID: membership)
        let legal = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        #expect(name.unicodeScalars.allSatisfy { legal.contains($0) })
    }
}
