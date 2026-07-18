import Combine
import ReadiumShared
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    @Published var categories: [HomeCategory] = []

    /// Every book exactly once, in My Library order — the source for search.
    ///
    /// `categories` deliberately repeats a book across every shelf it sits on,
    /// so `categories.flatMap(\.books)` yields duplicates and can't be used here.
    @Published private(set) var allBooks: [HomeBook] = []

    @Published var isLoading = true
    @Published var recentBook: HomeBook? = nil
    @Published var recentBookProgress: Double = 0
    @Published var recentFullBook: Book? = nil

    // Fixed UUID so "My Library" has a stable identity across loads
    static let myLibraryID = UUID(uuidString: "00000000-FADE-0000-0000-000000000001")!

    private let bookRepository: BookRepository
    private let categoryRepository: CategoryRepository

    // MARK: - UserDefaults keys for My Library ordering
    private static let myLibraryPositionKey = "fathom.myLibrarySortPosition"
    private static let myLibraryBookOrderKey = "fathom.myLibraryBookOrder"

    private static var myLibraryPosition: Int {
        get { UserDefaults.standard.integer(forKey: myLibraryPositionKey) }
        set { UserDefaults.standard.set(newValue, forKey: myLibraryPositionKey) }
    }

    private static var myLibraryBookOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: myLibraryBookOrderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: myLibraryBookOrderKey) }
    }

    // No default for categoryRepository: an accidental fallback to an
    // in-memory repo would silently discard the user's shelves.
    init(
        bookRepository: BookRepository,
        categoryRepository: CategoryRepository
    ) {
        self.bookRepository = bookRepository
        self.categoryRepository = categoryRepository
    }

    func load() async {
        isLoading = true
        async let books = bookRepository.listBooks()
        async let userCats = categoryRepository.listCategories()
        async let memberships = categoryRepository.listMemberships()
        let (fetchedBooks, fetchedCats, fetchedMemberships) = await (books, userCats, memberships)
        categories = Self.mapToCategories(
            fetchedBooks, userCategories: fetchedCats, memberships: fetchedMemberships)
        // My Library holds every book exactly once, already in the user's
        // persisted order — reuse it rather than re-deriving the ordering.
        allBooks = categories.first(where: { $0.id == Self.myLibraryID })?.books ?? []

        if let mostRecent = fetchedBooks.filter({ $0.lastReadAt != nil }).max(by: {
            $0.lastReadAt! < $1.lastReadAt!
        }) {
            recentFullBook = mostRecent
            recentBook = Self.makeHomeBook(mostRecent)
            recentBookProgress =
                ReadingStateStore.shared.loadLocator(forBookID: mostRecent.id)?.locations
                .totalProgression ?? 0
        } else {
            recentFullBook = nil
            recentBook = nil
            recentBookProgress = 0
        }

        isLoading = false
    }

    func recordOpened(book: Book) {
        recentFullBook = book
        recentBook = Self.makeHomeBook(book)
        recentBookProgress =
            ReadingStateStore.shared.loadLocator(forBookID: book.id)?.locations.totalProgression
            ?? 0
        Task { await bookRepository.touchLastReadAt(bookID: book.id) }
    }

    // Synchronous optimistic updates — callers can wrap these in withAnimation directly.
    // Each fires a background Task to persist; no load() needed.

    @discardableResult
    func createCategory(name: String, colorHex: String) -> HomeCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let record = BookCategory(
            id: UUID(), name: trimmed, shelfColorHex: colorHex, createdAt: Date())
        let category = HomeCategory(
            id: record.id, name: trimmed, books: [],
            shelfColor: Color(hex: colorHex), shelfColorHex: colorHex
        )
        categories.append(category)
        Task { await categoryRepository.addCategory(record) }
        return category
    }

    func updateCategory(id: UUID, name: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let idx = categories.firstIndex(where: { $0.id == id }) {
            let existing = categories[idx]
            categories[idx] = HomeCategory(
                id: id, name: trimmed, books: existing.books,
                shelfColor: Color(hex: colorHex), shelfColorHex: colorHex
            )
        }
        Task { await categoryRepository.updateCategory(id: id, name: trimmed, colorHex: colorHex) }
    }

    func deleteCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        Task { await categoryRepository.deleteCategory(id: id) }
    }

    func deleteBook(id: UUID) {
        for i in categories.indices {
            categories[i].books.removeAll { $0.id == id }
        }
        allBooks.removeAll { $0.id == id }
        if recentBook?.id == id {
            recentBook = nil
            recentFullBook = nil
        }
        Task {
            let allBooks = await bookRepository.listBooks()
            guard let book = allBooks.first(where: { $0.id == id }) else { return }
            // For iCloud files, removeItem works for both downloaded and
            // placeholder files (it removes from the cloud too).
            if let url = book.localURL {
                try? FileManager.default.removeItem(at: url)
            }
            if let coverFilename = book.coverFilename,
               let coverURL = BookFileStore.coverURL(for: coverFilename) {
                try? FileManager.default.removeItem(at: coverURL)
            }
            await bookRepository.deleteBook(book)
        }
    }

    func updateBook(id: UUID, customization: BookCustomization) async {
        let allBooks = await bookRepository.listBooks()
        guard var book = allBooks.first(where: { $0.id == id }) else { return }

        book.title = customization.title
        book.author = customization.author.isEmpty ? nil : customization.author
        book.description = customization.description.isEmpty ? nil : customization.description

        if customization.isCoverChanged {
            if let old = book.coverFilename, let url = BookFileStore.coverURL(for: old) {
                try? FileManager.default.removeItem(at: url)
            }
            if let data = customization.coverImageData,
               let filename = try? BookFileStore.saveCoverImage(data, coverID: UUID()) {
                book.coverFilename = filename
            } else {
                book.coverFilename = nil
            }
        }

        await bookRepository.updateBook(book)
        await load()
    }

    func toggleBookInCategory(bookID: UUID, categoryID: UUID) {
        guard let catIdx = categories.firstIndex(where: { $0.id == categoryID }) else { return }

        let alreadyIn = categories[catIdx].books.contains(where: { $0.id == bookID })

        if alreadyIn {
            categories[catIdx].books.removeAll { $0.id == bookID }
            Task {
                await categoryRepository.removeBookFromCategory(
                    bookID: bookID, categoryID: categoryID)
            }
        } else {
            if let source = categories.flatMap(\.books).first(where: { $0.id == bookID }) {
                var toAdd = source
                toAdd.categoryIDs.insert(categoryID)
                categories[catIdx].books.insert(toAdd, at: 0)
            }
            Task {
                await categoryRepository.addBookToCategory(bookID: bookID, categoryID: categoryID)
            }
        }

        // Keep categoryIDs in sync across every occurrence of this book (e.g. My Library row)
        for i in categories.indices {
            for j in categories[i].books.indices where categories[i].books[j].id == bookID {
                if alreadyIn {
                    categories[i].books[j].categoryIDs.remove(categoryID)
                } else {
                    categories[i].books[j].categoryIDs.insert(categoryID)
                }
            }
        }
    }

    // MARK: - Reordering

    // Called by ReorderShelvesSheet when the user taps Done with a final ordering.
    func applyShelfOrder(_ newOrder: [HomeCategory]) {
        categories = newOrder
        if let myLibIdx = newOrder.firstIndex(where: { $0.id == Self.myLibraryID }) {
            Self.myLibraryPosition = myLibIdx
        }
        let userCatIDs = newOrder.filter { !$0.shelfColorHex.isEmpty }.map(\.id)
        Task { await categoryRepository.reorderCategories(userCatIDs) }
    }

    // Called by ReorderBooksSheet when the user taps Done.
    func applyBookOrder(in categoryID: UUID, newOrder: [HomeBook]) {
        guard let catIdx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[catIdx].books = newOrder
        let bookIDs = newOrder.map(\.id)

        if categoryID == Self.myLibraryID {
            Self.myLibraryBookOrder = bookIDs.map(\.uuidString)
        } else {
            Task { await categoryRepository.reorderBooksInCategory(categoryID: categoryID, bookIDs: bookIDs) }
        }
    }

    // MARK: - Mapping

    private static func mapToCategories(
        _ books: [Book],
        userCategories: [BookCategory],
        memberships: [BookCategoryMembership]
    ) -> [HomeCategory] {
        // bookID → set of categoryIDs the book belongs to
        var bookCategoryIDs: [UUID: Set<UUID>] = [:]
        for m in memberships {
            bookCategoryIDs[m.bookID, default: []].insert(m.categoryID)
        }

        // categoryID → ordered list of member bookIDs
        var categoryBookIDs: [UUID: [UUID]] = [:]
        for m in memberships {
            categoryBookIDs[m.categoryID, default: []].append(m.bookID)
        }

        // Map every Book to its HomeBook, including which shelves it's on
        let bookByID: [UUID: Book] = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        func homeBook(from book: Book) -> HomeBook {
            HomeBook(
                id: book.id,
                title: book.title,
                author: book.author ?? "Unknown Author",
                coverColor: coverColor(for: book),
                textColor: textColor(for: book),
                coverFilename: book.coverFilename,
                categoryIDs: bookCategoryIDs[book.id] ?? []
            )
        }

        // Build user shelves in persisted sortOrder (already ordered by DB query)
        var userHomeCategories: [HomeCategory] = userCategories.map { cat in
            let memberBooks = (categoryBookIDs[cat.id] ?? []).compactMap { id in
                bookByID[id].map { homeBook(from: $0) }
            }
            return HomeCategory(
                id: cat.id,
                name: cat.name,
                books: memberBooks,
                shelfColor: Color(hex: cat.shelfColorHex),
                shelfColorHex: cat.shelfColorHex
            )
        }

        if books.isEmpty {
            return userHomeCategories
        }

        // Apply persisted book order for My Library (new books land at the front)
        let rawLibraryBooks = books
            .sorted { $0.importDate > $1.importDate }
            .map { homeBook(from: $0) }
        let savedOrder = Self.myLibraryBookOrder
        let libraryBooks: [HomeBook]
        if savedOrder.isEmpty {
            libraryBooks = rawLibraryBooks
        } else {
            let orderIndex = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
            let known = rawLibraryBooks
                .filter { orderIndex[$0.id.uuidString] != nil }
                .sorted { orderIndex[$0.id.uuidString]! < orderIndex[$1.id.uuidString]! }
            let newer = rawLibraryBooks.filter { orderIndex[$0.id.uuidString] == nil }
            libraryBooks = newer + known
        }

        let myLibrary = HomeCategory(
            id: Self.myLibraryID,
            name: "My Library",
            books: libraryBooks,
            shelfColor: AppTheme.default.colors.shelfAccent,
            shelfColorHex: ""
        )

        // Insert My Library at its persisted position
        let clampedPos = min(Self.myLibraryPosition, userHomeCategories.count)
        userHomeCategories.insert(myLibrary, at: clampedPos)
        return userHomeCategories
    }

    // Paired cover + text colors. Index is derived from the book's UUID so the
    // same book always gets the same color across app launches.
    static let coverPalette: [(cover: String, text: String)] = [
        ("1A5EA8", "FFFFFF"), ("E84B1F", "FFFFFF"), ("F5C518", "1A1A1A"),
        ("2A6B3E", "F5C518"), ("1A3A6B", "F5C518"), ("8B4513", "FFFFFF"),
        ("5B8A5E", "FFFFFF"), ("C0392B", "FFFFFF"), ("3A72D4", "FFFFFF"),
        ("7D3C98", "FFFFFF"), ("1ABC9C", "1A1A1A"), ("E67E22", "FFFFFF"),
    ]

    static func coverColor(for book: Book) -> Color {
        Color(hex: coverPalette[paletteIndex(for: book)].cover)
    }

    static func textColor(for book: Book) -> Color {
        Color(hex: coverPalette[paletteIndex(for: book)].text)
    }

    private static func paletteIndex(for book: Book) -> Int {
        StableHash.index(of: book.id, count: coverPalette.count)
    }

    /// Returns the cover background + text Color pair for any UUID.
    /// Used by the import flow to preview the palette colour before the book is saved.
    static func coverColorPair(for id: UUID) -> (cover: Color, text: Color) {
        let index = StableHash.index(of: id, count: coverPalette.count)
        let pair = coverPalette[index]
        return (Color(hex: pair.cover), Color(hex: pair.text))
    }

    static func makeHomeBook(_ book: Book, categoryIDs: Set<UUID> = []) -> HomeBook {
        HomeBook(
            id: book.id,
            title: book.title,
            author: book.author ?? "Unknown Author",
            coverColor: coverColor(for: book),
            textColor: textColor(for: book),
            coverFilename: book.coverFilename,
            categoryIDs: categoryIDs
        )
    }
}
