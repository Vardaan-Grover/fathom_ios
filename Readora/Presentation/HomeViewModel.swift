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
        let (fetchedBooks, fetchedCats) = await (books, userCats)
        categories = Self.mapToCategories(fetchedBooks, userCategories: fetchedCats)
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

    // MARK: - Mapping

    private static func mapToCategories(_ books: [Book], userCategories: [BookCategory]) -> [HomeCategory] {
        var result: [HomeCategory] = []

        if !books.isEmpty {
            let homeBooks = books.map { book in
                HomeBook(
                    id: book.id,
                    title: book.title,
                    author: book.author ?? "Unknown Author",
                    coverColor: coverColor(for: book),
                    textColor: textColor(for: book),
                    coverFilename: book.coverFilename
                )
            }
            result.append(HomeCategory(
                id: UUID(),
                name: "My Library",
                books: homeBooks,
                shelfColor: AppTheme.default.colors.shelfAccent,
                shelfColorHex: ""
            ))
        }

        for cat in userCategories {
            result.append(HomeCategory(
                id: cat.id,
                name: cat.name,
                books: [],
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

    static func makeHomeBook(_ book: Book) -> HomeBook {
        HomeBook(
            id: book.id,
            title: book.title,
            author: book.author ?? "Unknown Author",
            coverColor: coverColor(for: book),
            textColor: textColor(for: book),
            coverFilename: book.coverFilename
        )
    }
}
