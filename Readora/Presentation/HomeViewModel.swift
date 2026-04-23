import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var categories: [HomeCategory] = []
    @Published var isLoading = true

    private let bookRepository: BookRepository

    init(bookRepository: BookRepository) {
        self.bookRepository = bookRepository
    }

    func load() async {
        isLoading = true
        let books = await bookRepository.listBooks()
        categories = Self.mapToCategories(books)
        isLoading = false
    }

    // MARK: - Mapping

    private static func mapToCategories(_ books: [Book]) -> [HomeCategory] {
        guard !books.isEmpty else { return [] }

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

        return [
            HomeCategory(
                id: UUID(),
                name: "My Library",
                books: homeBooks,
                shelfColor: AppTheme.default.colors.shelfAccent  // ← Token, not a raw hex
            )
        ]
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
