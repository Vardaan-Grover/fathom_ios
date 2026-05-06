import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var categories: [HomeCategory] = []
    @Published var isLoading = true

    private let bookRepository: BookRepository
    private let categoryRepository: CategoryRepository

    init(bookRepository: BookRepository, categoryRepository: CategoryRepository = InMemoryCategoryRepository()) {
        self.bookRepository = bookRepository
        self.categoryRepository = categoryRepository
    }

    func load() async {
        isLoading = true
        async let books = bookRepository.listBooks()
        async let userCats = categoryRepository.listCategories()
        async let memberships = categoryRepository.listMemberships()
        let (fetchedBooks, fetchedCats, fetchedMemberships) = await (books, userCats, memberships)
        categories = Self.mapToCategories(fetchedBooks, userCategories: fetchedCats, memberships: fetchedMemberships)
        isLoading = false
    }

    // Synchronous optimistic updates — callers can wrap these in withAnimation directly.
    // Each fires a background Task to persist; no load() needed.

    func createCategory(name: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let record = BookCategory(id: UUID(), name: trimmed, shelfColorHex: colorHex, createdAt: Date())
        categories.append(HomeCategory(
            id: record.id, name: trimmed, books: [],
            shelfColor: Color(hex: colorHex), shelfColorHex: colorHex
        ))
        Task { await categoryRepository.addCategory(record) }
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

    func toggleBookInCategory(bookID: UUID, categoryID: UUID) {
        guard let catIdx = categories.firstIndex(where: { $0.id == categoryID }) else { return }

        let alreadyIn = categories[catIdx].books.contains(where: { $0.id == bookID })

        if alreadyIn {
            categories[catIdx].books.removeAll { $0.id == bookID }
            Task { await categoryRepository.removeBookFromCategory(bookID: bookID, categoryID: categoryID) }
        } else {
            if let source = categories.flatMap(\.books).first(where: { $0.id == bookID }) {
                var toAdd = source
                toAdd.categoryIDs.insert(categoryID)
                categories[catIdx].books.append(toAdd)
            }
            Task { await categoryRepository.addBookToCategory(bookID: bookID, categoryID: categoryID) }
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

        var result: [HomeCategory] = []

        if !books.isEmpty {
            result.append(HomeCategory(
                id: UUID(),
                name: "My Library",
                books: books.map { homeBook(from: $0) },
                shelfColor: AppTheme.default.colors.shelfAccent,
                shelfColorHex: ""
            ))
        }

        for cat in userCategories {
            let memberBooks = (categoryBookIDs[cat.id] ?? []).compactMap { id in
                bookByID[id].map { homeBook(from: $0) }
            }
            result.append(HomeCategory(
                id: cat.id,
                name: cat.name,
                books: memberBooks,
                shelfColor: Color(hex: cat.shelfColorHex),
                shelfColorHex: cat.shelfColorHex
            ))
        }

        return result
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
        abs(book.id.hashValue) % coverPalette.count
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
