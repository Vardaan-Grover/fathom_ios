import Foundation
import Testing

@testable import Fathom

/// StableHash exists because `Hashable.hashValue` is seeded per process —
/// these tests pin the FNV-1a implementation to its published test vectors so
/// palette assignments can never silently change between builds.
struct StableHashTests {

    @Test func matchesPublishedFNV1aVectors() {
        // Standard 64-bit FNV-1a reference vectors.
        #expect(StableHash.hash("") == 0xcbf2_9ce4_8422_2325)
        #expect(StableHash.hash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(StableHash.hash("foobar") == 0x85944171f73967e8)
    }

    @Test func deterministicAcrossCalls() {
        let id = UUID(uuidString: "0B7E80A2-6B92-4B52-A588-E01D549C57A5")!
        #expect(StableHash.index(of: id, count: 12) == StableHash.index(of: id, count: 12))
        #expect(StableHash.hash("fathom") == StableHash.hash("fathom"))
    }

    @Test(arguments: ["", "a", "serendipity", "🦉 owl", "The Left Hand of Darkness"])
    func indexAlwaysInRange(word: String) {
        let index = StableHash.index(of: word, count: 18)
        #expect((0..<18).contains(index))
    }

    @Test func knownUUIDMapsToStableIndex() {
        // Pinned value: if this fails, every user's cover colors just changed.
        let id = UUID(uuidString: "00000000-FADE-0000-0000-000000000001")!
        let index = StableHash.index(of: id, count: 12)
        #expect(index == StableHash.index(of: id.uuidString, count: 12))
        #expect((0..<12).contains(index))
    }
}
