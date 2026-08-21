import Foundation
import ReadiumShared
import Testing

@testable import Fathom

/// Position and furthest-progress resolve independently — see §3.6 of
/// docs/sync-conflict-policy.md.
struct ReadingStateStoreTests {

    private func makeStore() -> (ReadingStateStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-state-\(UUID().uuidString).json")
        return (ReadingStateStore(saveURLForTesting: url), url)
    }

    /// A locator at a given fraction through the publication. Built from JSON
    /// so the tests exercise the same decode path the app stores and syncs.
    private func locator(at progression: Double) throws -> Locator {
        let json = """
            {"href":"chapter.xhtml","type":"application/xhtml+xml",\
            "locations":{"totalProgression":\(progression)}}
            """
        return try #require(try Locator(jsonString: json))
    }

    // MARK: - High-water mark

    @Test("Reading forward raises the furthest mark")
    func forwardRaisesFurthest() throws {
        let (store, _) = makeStore()
        let bookID = UUID()

        store.saveLocator(try locator(at: 0.2), forBookID: bookID)
        #expect(store.furthestProgression(forBookID: bookID) == 0.2)

        store.saveLocator(try locator(at: 0.55), forBookID: bookID)
        #expect(store.furthestProgression(forBookID: bookID) == 0.55)
    }

    @Test("Reading backwards does not pull the furthest mark down")
    func backwardsKeepsFurthest() throws {
        let (store, _) = makeStore()
        let bookID = UUID()

        store.saveLocator(try locator(at: 0.8), forBookID: bookID)
        // Jumping back to re-read, or following a bookmark, moves the position
        // but must not rewrite history.
        store.saveLocator(try locator(at: 0.1), forBookID: bookID)

        #expect(store.furthestProgression(forBookID: bookID) == 0.8)
        let current = store.loadLocator(forBookID: bookID)?.locations.totalProgression
        #expect(current == 0.1)
    }

    // MARK: - Remote merge

    @Test("A newer remote position replaces the local one")
    func newerRemoteWins() throws {
        let (store, _) = makeStore()
        let bookID = UUID()

        store.saveLocator(try locator(at: 0.2), forBookID: bookID)
        let remoteLocator = try locator(at: 0.6)

        let replaced = store.applyRemoteState(
            locatorJSON: remoteLocator.jsonString!,
            savedAt: Date().addingTimeInterval(60),
            furthestProgression: 0.6,
            forBookID: bookID)

        #expect(replaced)
        #expect(store.loadLocator(forBookID: bookID)?.locations.totalProgression == 0.6)
        #expect(store.furthestProgression(forBookID: bookID) == 0.6)
    }

    @Test("An older remote position is ignored")
    func olderRemoteLoses() throws {
        let (store, _) = makeStore()
        let bookID = UUID()

        store.saveLocator(try locator(at: 0.5), forBookID: bookID)

        let replaced = store.applyRemoteState(
            locatorJSON: try locator(at: 0.1).jsonString!,
            savedAt: Date().addingTimeInterval(-3600),
            furthestProgression: 0.1,
            forBookID: bookID)

        #expect(!replaced)
        #expect(store.loadLocator(forBookID: bookID)?.locations.totalProgression == 0.5)
    }

    @Test("An older remote position still contributes its furthest mark")
    func olderRemoteStillRaisesFurthest() throws {
        let (store, _) = makeStore()
        let bookID = UUID()

        // This device is at 30% and wrote most recently.
        store.saveLocator(try locator(at: 0.3), forBookID: bookID)

        // The other device read all the way to 90% earlier, then stopped. Its
        // position loses the last-write-wins race, but the reader really did
        // get to 90% and that fact must survive.
        let replaced = store.applyRemoteState(
            locatorJSON: try locator(at: 0.9).jsonString!,
            savedAt: Date().addingTimeInterval(-3600),
            furthestProgression: 0.9,
            forBookID: bookID)

        #expect(!replaced)
        #expect(store.loadLocator(forBookID: bookID)?.locations.totalProgression == 0.3)
        #expect(store.furthestProgression(forBookID: bookID) == 0.9)
    }

    @Test("Applying the same remote state twice changes nothing")
    func remoteApplyIsIdempotent() throws {
        let (store, _) = makeStore()
        let bookID = UUID()
        let savedAt = Date()
        let json = try locator(at: 0.4).jsonString!

        store.applyRemoteState(locatorJSON: json, savedAt: savedAt,
                               furthestProgression: 0.4, forBookID: bookID)
        let first = store.state(forBookID: bookID)

        store.applyRemoteState(locatorJSON: json, savedAt: savedAt,
                               furthestProgression: 0.4, forBookID: bookID)
        #expect(store.state(forBookID: bookID) == first)
    }

    // MARK: - Persistence

    @Test("State survives a reload")
    func statePersists() throws {
        let (store, url) = makeStore()
        let bookID = UUID()

        store.saveLocator(try locator(at: 0.7), forBookID: bookID)
        store.saveLocator(try locator(at: 0.2), forBookID: bookID)
        store.flush()

        let reloaded = ReadingStateStore(saveURLForTesting: url)
        #expect(reloaded.furthestProgression(forBookID: bookID) == 0.7)
        #expect(reloaded.loadLocator(forBookID: bookID)?.locations.totalProgression == 0.2)
    }

    @Test("The legacy bookID-to-locator format is upgraded in place")
    func legacyFormatUpgrades() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-state-legacy-\(UUID().uuidString).json")
        let bookID = UUID()

        // The old on-disk shape: bookID → locator JSON, nothing else.
        let legacy = [bookID.uuidString: try locator(at: 0.45).jsonString!]
        try JSONEncoder().encode(legacy).write(to: url)

        let store = ReadingStateStore(saveURLForTesting: url)

        #expect(store.loadLocator(forBookID: bookID)?.locations.totalProgression == 0.45)
        // No high-water mark was recorded before, so the stored position is the
        // best available estimate of how far the reader got.
        #expect(store.furthestProgression(forBookID: bookID) == 0.45)
    }
}
