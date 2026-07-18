import Foundation

protocol CategoryRepository {
    func listCategories() async -> [BookCategory]
    func addCategory(_ category: BookCategory) async
    func updateCategory(id: UUID, name: String, colorHex: String) async
    func deleteCategory(id: UUID) async
    func listMemberships() async -> [BookCategoryMembership]
    func addBookToCategory(bookID: UUID, categoryID: UUID) async
    func removeBookFromCategory(bookID: UUID, categoryID: UUID) async
    func reorderCategories(_ ids: [UUID]) async
    func reorderBooksInCategory(categoryID: UUID, bookIDs: [UUID]) async
}

final actor InMemoryCategoryRepository: CategoryRepository {
    private var categories: [BookCategory] = []
    private var memberships: [BookCategoryMembership] = []

    func listCategories() async -> [BookCategory] { categories }
    func addCategory(_ category: BookCategory) async { categories.append(category) }
    func updateCategory(id: UUID, name: String, colorHex: String) async {
        guard let idx = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[idx].name = name
        categories[idx].shelfColorHex = colorHex
    }
    func deleteCategory(id: UUID) async {
        categories.removeAll { $0.id == id }
        memberships.removeAll { $0.categoryID == id }
    }
    func listMemberships() async -> [BookCategoryMembership] { memberships }
    func addBookToCategory(bookID: UUID, categoryID: UUID) async {
        guard !memberships.contains(where: { $0.bookID == bookID && $0.categoryID == categoryID }) else { return }
        memberships.append(BookCategoryMembership(bookID: bookID, categoryID: categoryID, addedAt: Date()))
    }
    func removeBookFromCategory(bookID: UUID, categoryID: UUID) async {
        memberships.removeAll { $0.bookID == bookID && $0.categoryID == categoryID }
    }

    func reorderCategories(_ ids: [UUID]) async {
        for (index, id) in ids.enumerated() {
            if let i = categories.firstIndex(where: { $0.id == id }) {
                categories[i].sortOrder = index
            }
        }
    }

    func reorderBooksInCategory(categoryID: UUID, bookIDs: [UUID]) async {
        for (index, bookID) in bookIDs.enumerated() {
            if let i = memberships.firstIndex(where: { $0.bookID == bookID && $0.categoryID == categoryID }) {
                memberships[i].sortOrder = index
            }
        }
    }
}

protocol BookRepository {
    func listBooks() async -> [Book]
    /// Books matching `query`, best match first. Empty/punctuation-only queries
    /// return [] — callers show the full library rather than searching for it.
    func searchBooks(query: String) async -> [Book]
    func addBook(_ book: Book) async
    func updateBook(_ book: Book) async
    func deleteBook(_ book: Book) async
    func touchLastReadAt(bookID: UUID) async
    func logReadingSession(for bookID: UUID, duration: TimeInterval) async
    func listReadingActivity(forYear year: Int) async -> [ReadingActivity]
    func insertMockReadingActivity(_ activity: ReadingActivity) async
    func deleteAllReadingActivity(forYear year: Int) async
}

final actor InMemoryBookRepository: BookRepository {
    private var books: [Book] = [
        Book(id: UUID(), title: "Demo Book", author: "Demo Author", format: .epub, localFilename: nil)
    ]

    func listBooks() async -> [Book] {
        books
    }

    /// Previews and tests only — a token-prefix scan standing in for FTS5.
    /// Match semantics mirror `matchExpression`: every token must prefix-match
    /// somewhere. Ranking is title-before-author-before-description rather than
    /// bm25, which is close enough for a handful of fixture books.
    func searchBooks(query: String) async -> [Book] {
        let tokens = LibrarySearch.tokens(in: query).map { $0.lowercased() }
        guard !tokens.isEmpty else { return [] }

        func fold(_ s: String?) -> String {
            (s ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        }
        func rank(_ book: Book) -> Int? {
            let fields = [fold(book.title), fold(book.author), fold(book.description)]
            var best = Int.max
            for token in tokens {
                guard let hit = fields.firstIndex(where: { field in
                    field.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                        .contains { $0.hasPrefix(token) }
                }) else { return nil }  // every token must match somewhere
                best = min(best, hit)
            }
            return best
        }

        return books.compactMap { book in rank(book).map { ($0, book) } }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    func addBook(_ book: Book) async { books.append(book) }

    func updateBook(_ book: Book) async {
        guard let idx = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[idx] = book
    }

    func deleteBook(_ book: Book) async {
        books.removeAll { $0.id == book.id }
    }

    func touchLastReadAt(bookID: UUID) async {
        guard let idx = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[idx].lastReadAt = Date()
    }

    func logReadingSession(for bookID: UUID, duration: TimeInterval) async {}
    func listReadingActivity(forYear year: Int) async -> [ReadingActivity] { return [] }
    func insertMockReadingActivity(_ activity: ReadingActivity) async {}
    func deleteAllReadingActivity(forYear year: Int) async {}
}
