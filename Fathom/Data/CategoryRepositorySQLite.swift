import Foundation
import GRDB

final actor CategoryRepositorySQLite: CategoryRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func listCategories() async -> [BookCategory] {
        do {
            return try await dbQueue.read { db in
                try BookCategory.order(Column("sortOrder"), Column("createdAt")).fetchAll(db)
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
            return []
        }
    }

    func addCategory(_ category: BookCategory) async {
        do {
            try await dbQueue.write { db in
                // Place new shelf after all existing ones
                let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM bookCategories") ?? -1
                var ordered = category
                ordered.sortOrder = maxOrder + 1
                try ordered.insert(db)
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

    func updateCategory(id: UUID, name: String, colorHex: String) async {
        do {
            try await dbQueue.write { db in
                // fetchOne(db, key:) uses UUID.databaseValue (blob), matching what insert() stores
                if var category = try BookCategory.fetchOne(db, key: id) {
                    category.name = name
                    category.shelfColorHex = colorHex
                    try category.update(db)
                }
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

    func deleteCategory(id: UUID) async {
        do {
            try await dbQueue.write { db in
                _ = try BookCategory.deleteOne(db, key: id)
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

    func listMemberships() async -> [BookCategoryMembership] {
        do {
            return try await dbQueue.read { db in
                try BookCategoryMembership
                    // Removed memberships stay as tombstones so the removal can
                    // reach other devices; they are not on the shelf.
                    .filter(Column("deletedAt") == nil)
                    .order(Column("categoryID"), Column("sortOrder"), Column("addedAt").desc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
            return []
        }
    }

    func addBookToCategory(bookID: UUID, categoryID: UUID) async {
        do {
            try await dbQueue.write { db in
                // A row may already exist as a tombstone from an earlier
                // removal. Re-adding has to clear it rather than be ignored by
                // the primary key — otherwise a book removed from a shelf could
                // never be put back.
                //
                // Fetch-then-write, not an upsert: a statement with its own
                // ON CONFLICT clause overrides the conflict resolution inside
                // the CDC trigger it fires, breaking the sync queue.
                if var existing = try BookCategoryMembership
                    .filter(Column("bookID") == bookID && Column("categoryID") == categoryID)
                    .fetchOne(db) {
                    guard existing.deletedAt != nil else { return }
                    existing.deletedAt = nil
                    existing.modifiedAt = Date()
                    try existing.update(db)
                } else {
                    try BookCategoryMembership(bookID: bookID,
                                               categoryID: categoryID,
                                               addedAt: Date()).insert(db)
                }
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

    func removeBookFromCategory(bookID: UUID, categoryID: UUID) async {
        do {
            try await dbQueue.write { db in
                // Tombstone rather than delete: a hard delete carries no
                // evidence it happened, so a device that was offline during the
                // removal cannot tell it from "not synced yet" and re-adds the
                // book. See §3.3 of docs/sync-conflict-policy.md.
                guard var existing = try BookCategoryMembership
                    .filter(Column("bookID") == bookID && Column("categoryID") == categoryID)
                    .fetchOne(db), existing.deletedAt == nil else { return }
                let now = Date()
                existing.deletedAt = now
                existing.modifiedAt = now
                try existing.update(db)
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

    func reorderCategories(_ ids: [UUID]) async {
        do {
            try await dbQueue.write { db in
                for (index, id) in ids.enumerated() {
                    // Bind UUID directly — GRDB encodes it to match the stored blob format
                    try db.execute(
                        sql: "UPDATE bookCategories SET sortOrder = ? WHERE id = ?",
                        arguments: [index, id]
                    )
                }
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

    func reorderBooksInCategory(categoryID: UUID, bookIDs: [UUID]) async {
        do {
            try await dbQueue.write { db in
                for (index, bookID) in bookIDs.enumerated() {
                    // Skips tombstones: reordering a shelf must not silently
                    // resurrect a book that was removed from it.
                    try db.execute(
                        sql: "UPDATE bookCategoryMemberships SET sortOrder = ?, modifiedAt = ? "
                           + "WHERE bookID = ? AND categoryID = ? AND deletedAt IS NULL",
                        arguments: [index, Date(), bookID, categoryID]
                    )
                }
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

}
