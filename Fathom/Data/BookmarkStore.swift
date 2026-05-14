import Foundation
import GRDB

final class BookmarkStore {
    static let shared = BookmarkStore()

    static let didChangeNotification = Notification.Name("BookmarkStore.didChange")

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    private init() {}

    func add(_ bookmark: Bookmark) {
        do {
            try dbQueue.write { db in
                try bookmark.insert(db)
            }
            notifyChange(bookID: bookmark.bookID)
        } catch {
            AppLogger.log(tag: "BookmarkStore", "Error adding bookmark: \(error)")
        }
    }

    func delete(id: UUID) {
        var bookID: UUID?
        do {
            try dbQueue.write { db in
                if let bookmark = try Bookmark.fetchOne(db, id: id) {
                    bookID = bookmark.bookID
                    _ = try Bookmark.deleteOne(db, id: id)
                }
            }
            if let bookID { notifyChange(bookID: bookID) }
        } catch {
            AppLogger.log(tag: "BookmarkStore", "Error deleting bookmark: \(error)")
        }
    }

    func bookmarks(forBookID bookID: UUID) -> [Bookmark] {
        do {
            return try dbQueue.read { db in
                try Bookmark
                    .filter(Column("bookID") == bookID)
                    .order(Column("progression").asc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "BookmarkStore", "Error fetching bookmarks: \(error)")
            return []
        }
    }

    /// Returns the bookmark at `progression` (within `tolerance`) if one exists.
    func bookmark(forBookID bookID: UUID, progression: Double, tolerance: Double = 0.01) -> Bookmark? {
        bookmarks(forBookID: bookID).first { abs($0.progression - progression) <= tolerance }
    }

    /// Adds a bookmark if none exists at this progression; deletes it if one does. Returns `true` if added.
    @discardableResult
    func toggle(
        bookID: UUID,
        progression: Double,
        locatorJSON: String,
        chapterTitle: String?,
        pageNumber: Int?,
        tolerance: Double = 0.01
    ) -> Bool {
        if let existing = bookmark(forBookID: bookID, progression: progression, tolerance: tolerance) {
            delete(id: existing.id)
            return false
        } else {
            add(Bookmark(
                bookID: bookID,
                locatorJSON: locatorJSON,
                progression: progression,
                chapterTitle: chapterTitle,
                pageNumber: pageNumber
            ))
            return true
        }
    }

    private func notifyChange(bookID: UUID) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: bookID
            )
        }
    }
}
