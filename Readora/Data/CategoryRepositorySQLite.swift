import Foundation
import GRDB

final actor CategoryRepositorySQLite: CategoryRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func listCategories() async -> [BookCategory] {
        await withCheckedContinuation { continuation in
            do {
                let categories = try dbQueue.read { db in
                    try BookCategory.order(Column("createdAt")).fetchAll(db)
                }
                continuation.resume(returning: categories)
            } catch {
                AppLogger.logError(tag: "CategoryRepository", error)
                continuation.resume(returning: [])
            }
        }
    }

    func addCategory(_ category: BookCategory) async {
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in
                    try category.insert(db)
                }
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "CategoryRepository", error)
                continuation.resume()
            }
        }
    }

    func deleteCategory(_ category: BookCategory) async {
        await withCheckedContinuation { continuation in
            do {
                try dbQueue.write { db in
                    _ = try category.delete(db)
                }
                continuation.resume()
            } catch {
                AppLogger.logError(tag: "CategoryRepository", error)
                continuation.resume()
            }
        }
    }
}
