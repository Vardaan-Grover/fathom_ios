import Foundation

/// Deterministic hashing for values that must map to the same result on every
/// launch (e.g. palette color assignment).
///
/// Swift's `Hashable.hashValue` is seeded per-process, so `id.hashValue % n`
/// gives a different answer each run — book covers and word cards would
/// reshuffle colors on every launch. FNV-1a over the value's stable string
/// form does not have that problem.
enum StableHash {
    /// FNV-1a hash of the string's UTF-8 bytes.
    static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A stable index in `0..<count` for the given string. `count` must be > 0.
    static func index(of string: String, count: Int) -> Int {
        Int(hash(string) % UInt64(count))
    }

    /// A stable index in `0..<count` for the given UUID. `count` must be > 0.
    static func index(of id: UUID, count: Int) -> Int {
        index(of: id.uuidString, count: count)
    }
}
