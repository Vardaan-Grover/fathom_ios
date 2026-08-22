import Foundation
import ReadiumShared
import Testing

@testable import Fathom

/// "You read to 60% on another device — jump there?"
///
/// The whole difficulty is deciding when *not* to ask. `furthestProgression`
/// is raised by this device's own reading too, so offering off that mark would
/// prompt every time the reader turned back a chapter on the phone in their
/// hand. Only what another device contributed can earn the question.
struct ReadingJumpOfferTests {

    private func makeStore() -> ReadingStateStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jump-offer-\(UUID().uuidString).json")
        return ReadingStateStore(saveURLForTesting: url)
    }

    /// A locator at a given progression, which is all the offer logic reads.
    private func locatorJSON(at progression: Double) -> String {
        #"{"href":"ch1.html","type":"text/html","locations":{"totalProgression":\#(progression)}}"#
    }

    private func remoteState(_ store: ReadingStateStore,
                             bookID: UUID,
                             position: Double,
                             furthest: Double,
                             savedAt: Date) {
        _ = store.applyRemoteState(locatorJSON: locatorJSON(at: position),
                                   savedAt: savedAt,
                                   furthestProgression: furthest,
                                   forBookID: bookID)
    }

    // MARK: - Not asking

    @Test("Nothing to offer when no other device has been heard from")
    func silentWithoutRemoteState() throws {
        let store = makeStore()
        let bookID = UUID()
        store.saveLocator(try locator(at: 0.10), forBookID: bookID)

        #expect(store.jumpOffer(forBookID: bookID) == nil)
    }

    @Test("Reading far ahead then turning back on this device does not prompt")
    func ownProgressNeverPrompts() throws {
        // The regression this design exists to prevent. The high-water mark is
        // at 0.60 and the position at 0.10, purely from this device — asking
        // here would nag the reader about their own deliberate navigation.
        let store = makeStore()
        let bookID = UUID()

        store.saveLocator(try locator(at: 0.60), forBookID: bookID)
        store.saveLocator(try locator(at: 0.10), forBookID: bookID)

        #expect(store.furthestProgression(forBookID: bookID) == 0.60)
        #expect(store.jumpOffer(forBookID: bookID) == nil, "that 60% was this device's own")
    }

    @Test("A difference of a few pages is not worth a prompt")
    func trivialGapIsIgnored() {
        let store = makeStore()
        let bookID = UUID()
        let now = Date()

        remoteState(store, bookID: bookID, position: 0.50, furthest: 0.505, savedAt: now)
        // The other device is one page ahead. Almost certainly it is just the
        // same reader, mid-session, on the phone they put down a minute ago.
        #expect(store.jumpOffer(forBookID: bookID) == nil)
    }

    // MARK: - Asking

    @Test("A device that got meaningfully further is offered")
    func remoteProgressIsOffered() throws {
        let store = makeStore()
        let bookID = UUID()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        // The other phone read to 60%, a while ago.
        remoteState(store, bookID: bookID, position: 0.60, furthest: 0.60, savedAt: earlier)
        // Then this one opened the book at the start, which is a newer write
        // and so wins the position. That is the trap the offer exists for.
        store.saveLocator(try locator(at: 0.10), forBookID: bookID)

        #expect(store.jumpOffer(forBookID: bookID) == 0.60)
    }

    @Test("Declining retires that offer")
    func decliningIsRemembered() throws {
        let store = makeStore()
        let bookID = UUID()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        remoteState(store, bookID: bookID, position: 0.60, furthest: 0.60, savedAt: earlier)
        store.saveLocator(try locator(at: 0.10), forBookID: bookID)
        #expect(store.jumpOffer(forBookID: bookID) == 0.60)

        store.declineJump(forBookID: bookID)
        #expect(store.jumpOffer(forBookID: bookID) == nil)
    }

    @Test("A declined offer returns when the other device gets further still")
    func decliningIsNotForever() throws {
        let store = makeStore()
        let bookID = UUID()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        remoteState(store, bookID: bookID, position: 0.60, furthest: 0.60, savedAt: earlier)
        store.saveLocator(try locator(at: 0.10), forBookID: bookID)
        store.declineJump(forBookID: bookID)

        // Another evening's reading on the other phone is new information.
        remoteState(store, bookID: bookID, position: 0.85, furthest: 0.85, savedAt: earlier)
        #expect(store.jumpOffer(forBookID: bookID) == 0.85)
    }

    @Test("Reading past the mark on this device retires the offer")
    func catchingUpEndsTheOffer() throws {
        // No flag to clear: the offer is a live comparison against the current
        // position, so simply arriving there answers it.
        let store = makeStore()
        let bookID = UUID()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        remoteState(store, bookID: bookID, position: 0.60, furthest: 0.60, savedAt: earlier)
        store.saveLocator(try locator(at: 0.10), forBookID: bookID)
        #expect(store.jumpOffer(forBookID: bookID) == 0.60)

        store.saveLocator(try locator(at: 0.62), forBookID: bookID)
        #expect(store.jumpOffer(forBookID: bookID) == nil)
    }

    // MARK: - Persistence

    @Test("A position write does not discard what the other device reported")
    func localWritePreservesTheOffer() throws {
        // saveLocator builds a fresh ReadingState. Before this was handled, a
        // single page turn between the sync landing and the book opening threw
        // the offer away.
        let store = makeStore()
        let bookID = UUID()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        remoteState(store, bookID: bookID, position: 0.60, furthest: 0.60, savedAt: earlier)
        store.saveLocator(try locator(at: 0.10), forBookID: bookID)
        store.saveLocator(try locator(at: 0.11), forBookID: bookID)
        store.saveLocator(try locator(at: 0.12), forBookID: bookID)

        #expect(store.jumpOffer(forBookID: bookID) == 0.60)
    }

    @Test("Reading state written before these fields existed still loads")
    func legacyStateDecodes() throws {
        // The fields are Optional so the synthesized Codable uses
        // decodeIfPresent. A non-optional would throw on the missing key and
        // take every saved position with it.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).json")
        let bookID = UUID()
        let legacy = """
            {"\(bookID.uuidString)":{"locatorJSON":"{}","savedAt":757400000,\
            "furthestProgression":0.42}}
            """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let store = ReadingStateStore(saveURLForTesting: url)
        #expect(store.furthestProgression(forBookID: bookID) == 0.42)
        #expect(store.jumpOffer(forBookID: bookID) == nil)
    }

    // MARK: - Helper

    /// A real Readium locator at a given progression — the offer logic reads
    /// `locations.totalProgression` and nothing else.
    private func locator(at progression: Double) throws -> Locator {
        try #require(try? Locator(jsonString: locatorJSON(at: progression)))
    }
}
