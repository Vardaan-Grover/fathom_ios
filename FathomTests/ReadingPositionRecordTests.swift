import CloudKit
import Foundation
import Testing

@testable import Fathom

/// Reading position is the one synced value with no `CloudKitSyncable`
/// conformance — it lives in a file, not a table — so its CloudKit field names
/// are the only ones written out by hand on both sides. These tests are what
/// stops a rename on one side from silently ending position sync.
struct ReadingPositionRecordTests {

    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    private func record(named name: String = "ReadingPosition.x") -> CKRecord {
        CKRecord(recordType: CKRecordType.readingPosition,
                 recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
    }

    private func makeStore() -> ReadingStateStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-state-\(UUID().uuidString).json")
        return ReadingStateStore(saveURLForTesting: url)
    }

    // MARK: - Round trip

    @Test("A position survives the trip through a CKRecord")
    func roundTrips() throws {
        let bookID = UUID()
        // Whole seconds: CloudKit stores timestamps at a coarser resolution
        // than Date carries, and this test is about field names, not float
        // comparison.
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ReadingState(locatorJSON: #"{"href":"ch1.html","locations":{"totalProgression":0.42}}"#,
                                 savedAt: savedAt,
                                 furthestProgression: 0.67)

        let ckRecord = record()
        ReadingPositionRecord.write(state, bookID: bookID, into: ckRecord)
        let restored = try #require(ReadingPositionRecord.read(ckRecord))

        #expect(restored.bookID == bookID)
        #expect(restored.state.locatorJSON == state.locatorJSON)
        #expect(restored.state.savedAt == savedAt)
        #expect(restored.state.furthestProgression == 0.67)
    }

    @Test("The field names are the ones the deployed schema declares")
    func fieldNamesMatchSchema() {
        // CloudKit's production schema is additive-only, so these strings are a
        // one-way door. Asserting them here means a rename has to be a
        // deliberate act rather than a refactor that compiles.
        let ckRecord = record()
        ReadingPositionRecord.write(
            ReadingState(locatorJSON: "{}", savedAt: Date(), furthestProgression: 0.1),
            bookID: UUID(), into: ckRecord)

        #expect(ckRecord["bookID"] as? String != nil)
        #expect(ckRecord["locatorJSON"] as? String != nil)
        #expect(ckRecord["savedAt"] as? Date != nil)
        #expect(ckRecord["furthestProgression"] as? Double != nil)
    }

    // MARK: - Rejection

    @Test("A record with no savedAt is rejected rather than defaulted")
    func missingSavedAtIsRejected() {
        // savedAt decides which of two positions wins. Defaulting it would
        // stamp the record with the distant past, so it would lose every
        // conflict forever and the position would never move again.
        let ckRecord = record()
        ckRecord["bookID"] = UUID().uuidString
        ckRecord["locatorJSON"] = "{}"

        #expect(ReadingPositionRecord.read(ckRecord) == nil)
    }

    @Test("A missing furthestProgression contributes nothing rather than resetting")
    func missingProgressionDefaultsToZero() {
        // Unlike savedAt this one is safe to default: it merges by max, so zero
        // cannot pull an existing mark down.
        let ckRecord = record()
        ckRecord["bookID"] = UUID().uuidString
        ckRecord["locatorJSON"] = "{}"
        ckRecord["savedAt"] = Date()

        #expect(ReadingPositionRecord.read(ckRecord)?.state.furthestProgression == 0)
    }

    // MARK: - End to end

    @Test("A record from the other device lands as the winning position")
    func remoteRecordAppliesThroughTheStore() throws {
        let store = makeStore()
        let bookID = UUID()
        let early = Date(timeIntervalSince1970: 1_700_000_000)

        _ = store.applyRemoteState(locatorJSON: #"{"href":"ch1.html"}"#,
                                   savedAt: early,
                                   furthestProgression: 0.30,
                                   forBookID: bookID)

        // The other phone, further on and later.
        let ckRecord = record()
        ReadingPositionRecord.write(
            ReadingState(locatorJSON: #"{"href":"ch9.html"}"#,
                         savedAt: early.addingTimeInterval(60),
                         furthestProgression: 0.80),
            bookID: bookID, into: ckRecord)

        let incoming = try #require(ReadingPositionRecord.read(ckRecord))
        let took = store.applyRemoteState(locatorJSON: incoming.state.locatorJSON,
                                          savedAt: incoming.state.savedAt,
                                          furthestProgression: incoming.state.furthestProgression,
                                          forBookID: incoming.bookID)

        #expect(took)
        let final = try #require(store.state(forBookID: bookID))
        #expect(final.locatorJSON == #"{"href":"ch9.html"}"#)
        #expect(final.furthestProgression == 0.80)
    }

    @Test("A stale record from the other device cannot drag the reader backwards")
    func staleRecordLosesButStillRaisesTheMark() throws {
        // The case the two fields exist to separate: the other device wrote
        // earlier, so its position loses — but it had read further at some
        // point, and that much is still true.
        let store = makeStore()
        let bookID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        _ = store.applyRemoteState(locatorJSON: #"{"href":"ch5.html"}"#,
                                   savedAt: now,
                                   furthestProgression: 0.50,
                                   forBookID: bookID)

        let ckRecord = record()
        ReadingPositionRecord.write(
            ReadingState(locatorJSON: #"{"href":"ch2.html"}"#,
                         savedAt: now.addingTimeInterval(-3600),
                         furthestProgression: 0.90),
            bookID: bookID, into: ckRecord)

        let incoming = try #require(ReadingPositionRecord.read(ckRecord))
        let took = store.applyRemoteState(locatorJSON: incoming.state.locatorJSON,
                                          savedAt: incoming.state.savedAt,
                                          furthestProgression: incoming.state.furthestProgression,
                                          forBookID: incoming.bookID)

        #expect(!took, "an older position must not replace a newer one")
        let final = try #require(store.state(forBookID: bookID))
        #expect(final.locatorJSON == #"{"href":"ch5.html"}"#, "the reader stays where they were")
        #expect(final.furthestProgression == 0.90, "but the high-water mark still moves")
    }
}
