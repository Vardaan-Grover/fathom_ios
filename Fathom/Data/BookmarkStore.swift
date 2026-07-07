import Foundation
import GRDB

final class BookmarkStore {
    static let shared = BookmarkStore()

    static let didChangeNotification = Notification.Name("BookmarkStore.didChange")

    private var dbQueue: DatabaseQueue { DatabaseManager.shared.dbQueue }

    private init() {}

    // Writes are asynchronous so callers (often on the main thread) never
    // block on the database — observers refresh via didChangeNotification
    // once the write commits.

    func add(_ bookmark: Bookmark) {
        dbQueue.asyncWrite({ db in
            try bookmark.insert(db)
        }, completion: { _, result in
            switch result {
            case .success:
                Self.notifyChange(bookID: bookmark.bookID)
            case .failure(let error):
                AppLogger.log(tag: "BookmarkStore", "Error adding bookmark: \(error)")
            }
        })
    }

    func delete(id: UUID) {
        dbQueue.asyncWrite({ db -> UUID? in
            guard var bookmark = try Bookmark.fetchOne(db, id: id) else { return nil }
            bookmark.deletedAt = Date()
            try bookmark.update(db)
            return bookmark.bookID
        }, completion: { _, result in
            switch result {
            case .success(let bookID):
                if let bookID { Self.notifyChange(bookID: bookID) }
            case .failure(let error):
                AppLogger.log(tag: "BookmarkStore", "Error soft-deleting bookmark: \(error)")
            }
        })
    }

    func bookmarks(forBookID bookID: UUID) -> [Bookmark] {
        do {
            return try dbQueue.read { db in
                try Bookmark
                    .filter(Column("bookID") == bookID && Column("deletedAt") == nil)
                    .order(Column("progression").asc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "BookmarkStore", "Error fetching bookmarks: \(error)")
            return []
        }
    }

    /// All non-deleted bookmarks across every book, newest first.
    func allBookmarks() -> [Bookmark] {
        do {
            return try dbQueue.read { db in
                try Bookmark
                    .filter(Column("deletedAt") == nil)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        } catch {
            AppLogger.log(tag: "BookmarkStore", "Error fetching all bookmarks: \(error)")
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

    private static func notifyChange(bookID: UUID) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: bookID
            )
        }
    }
}
