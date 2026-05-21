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
                let membership = BookCategoryMembership(bookID: bookID, categoryID: categoryID, addedAt: Date())
                try membership.insert(db, onConflict: .ignore)
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

    func removeBookFromCategory(bookID: UUID, categoryID: UUID) async {
        do {
            try await dbQueue.write { db in
                try BookCategoryMembership
                    .filter(Column("bookID") == bookID && Column("categoryID") == categoryID)
                    .deleteAll(db)
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
                    try db.execute(
                        sql: "UPDATE bookCategoryMemberships SET sortOrder = ? WHERE bookID = ? AND categoryID = ?",
                        arguments: [index, bookID, categoryID]
                    )
                }
            }
        } catch {
            AppLogger.logError(tag: "CategoryRepository", error)
        }
    }

}
