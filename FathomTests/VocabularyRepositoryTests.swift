import Foundation
import GRDB
import Testing

@testable import Fathom

/// `removeSavedWord` and `setPinnedAt` update `saved_words` through raw SQL.
/// Rows get there via GRDB's `insert`/`upsert`, which store `id` as a 16-byte
/// blob, so the `WHERE id = ?` binding has to be the UUID itself — binding
/// `id.uuidString` compares a blob against a string, matches nothing, and the
/// UPDATE silently affects 0 rows. Same class of bug as the one fixed in
/// `BookRepositorySQLite.logReadingSession`.
struct VocabularyRepositoryTests {

    nonisolated private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    nonisolated private func makeWord(_ word: String = "sidereal") -> SavedWord {
        SavedWord(
            id: UUID(),
            word: word,
            language: "en",
            partsOfSpeech: "adjective",
            bookID: nil,
            bookTitle: nil,
            chapter: nil,
            pageNumber: nil,
            locatorJSON: nil,
            contextSentence: nil,
            fullDictionaryJSON: nil)
    }

    /// Reads the columns straight out of SQLite rather than through the
    /// repository, so a fetch that shared the same binding bug could not mask
    /// an UPDATE that did nothing.
    nonisolated private func row(_ dbQueue: DatabaseQueue, _ id: UUID) throws -> Row? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db, sql: "SELECT pinnedAt, deletedAt FROM saved_words WHERE id = ?",
                arguments: [id])
        }
    }

    @Test("Pinning a saved word actually sets pinnedAt")
    func setPinnedAtWritesTheColumn() async throws {
        let dbQueue = try makeMigratedQueue()
        let repo = VocabularyRepositorySQLite(dbQueue: dbQueue)
        let word = makeWord()
        await repo.addSavedWord(word)

        let pinnedAt = Date(timeIntervalSince1970: 1_700_000_000)
        await repo.setPinnedAt(id: word.id, pinnedAt: pinnedAt)

        let stored = try #require(try row(dbQueue, word.id))
        #expect(stored["pinnedAt"] as Date? == pinnedAt)

        // Unpinning clears it again.
        await repo.setPinnedAt(id: word.id, pinnedAt: nil)
        let unpinned = try #require(try row(dbQueue, word.id))
        #expect(unpinned["pinnedAt"] as Date? == nil)
    }

    @Test("Removing a saved word actually sets the deletedAt tombstone")
    func removeSavedWordWritesTheTombstone() async throws {
        let dbQueue = try makeMigratedQueue()
        let repo = VocabularyRepositorySQLite(dbQueue: dbQueue)
        let word = makeWord()
        await repo.addSavedWord(word)

        await repo.removeSavedWord(id: word.id)

        let stored = try #require(try row(dbQueue, word.id))
        #expect(stored["deletedAt"] as Date? != nil)

        // The soft-deleted word drops out of the list the UI reads.
        let listed = await repo.listSavedWords()
        #expect(!listed.contains { $0.id == word.id })
    }

    @Test("A soft-deleted word stays out of the list while others remain")
    func removeOnlyAffectsTheTargetedWord() async throws {
        let dbQueue = try makeMigratedQueue()
        let repo = VocabularyRepositorySQLite(dbQueue: dbQueue)
        let doomed = makeWord("ecliptic")
        let kept = makeWord("azimuth")
        await repo.addSavedWord(doomed)
        await repo.addSavedWord(kept)

        await repo.removeSavedWord(id: doomed.id)

        let listed = await repo.listSavedWords()
        #expect(listed.map(\.id) == [kept.id])
    }
}
