import Foundation
import GRDB

public protocol VocabularyRepository: Actor {
    func listSavedWords() async -> [SavedWord]
    func addSavedWord(_ word: SavedWord) async
    func updateSavedWord(_ word: SavedWord) async
    func removeSavedWord(id: UUID) async
    func getSavedWord(word: String, language: String) async -> SavedWord?
    func setPinnedAt(id: UUID, pinnedAt: Date?) async
}

public final actor VocabularyRepositorySQLite: VocabularyRepository {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func listSavedWords() async -> [SavedWord] {
        do {
            return try await dbQueue.read { db in
                // Pinned words first (most recently pinned first), then by newest saved.
                // Exclude soft-deleted tombstones.
                try SavedWord
                    .filter(Column("deletedAt") == nil)
                    .order(Column("pinnedAt").desc, Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "VocabularyRepository", "Error listing saved words: \(error)")
            return []
        }
    }

    public func addSavedWord(_ word: SavedWord) async {
        do {
            try await dbQueue.write { db in
                try word.insert(db)
            }
        } catch {
            AppLogger.log(tag: "VocabularyRepository", "Error adding saved word: \(error)")
        }
    }

    public func updateSavedWord(_ word: SavedWord) async {
        do {
            try await dbQueue.write { db in
                try word.update(db)
            }
        } catch {
            AppLogger.log(tag: "VocabularyRepository", "Error updating saved word: \(error)")
        }
    }

    public func removeSavedWord(id: UUID) async {
        do {
            try await dbQueue.write { db in
                // `id` is bound as a UUID, not `id.uuidString`. Rows are written
                // through GRDB (`word.insert(db)` here, `upsert(db)` on the sync
                // path), and GRDB stores UUID as a 16-byte blob — a blob never
                // equals a string, so binding the string matched nothing and the
                // UPDATE silently affected 0 rows. Same bug as the one fixed in
                // BookRepositorySQLite.logReadingSession; see the notes there.
                try db.execute(
                    sql: "UPDATE saved_words SET deletedAt = ? WHERE id = ?",
                    arguments: [Date(), id]
                )
            }
        } catch {
            AppLogger.log(tag: "VocabularyRepository", "Error soft-deleting saved word: \(error)")
        }
    }

    public func setPinnedAt(id: UUID, pinnedAt: Date?) async {
        do {
            try await dbQueue.write { db in
                // Bound as a UUID — see removeSavedWord above.
                try db.execute(
                    sql: "UPDATE saved_words SET pinnedAt = ? WHERE id = ?",
                    arguments: [pinnedAt, id]
                )
            }
        } catch {
            AppLogger.log(tag: "VocabularyRepository", "Error setting pinnedAt: \(error)")
        }
    }

    public func getSavedWord(word: String, language: String) async -> SavedWord? {
        do {
            return try await dbQueue.read { db in
                try SavedWord
                    .filter(
                        Column("word") == word && Column("language") == language
                            && Column("deletedAt") == nil
                    )
                    .fetchOne(db)
            }
        } catch {
            AppLogger.log(tag: "VocabularyRepository", "Error fetching saved word: \(error)")
            return nil
        }
    }
}
