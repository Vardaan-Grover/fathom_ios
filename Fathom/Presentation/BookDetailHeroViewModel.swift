import Combine
import ReadiumShared
import SwiftUI

@MainActor
final class BookDetailHeroViewModel: ObservableObject {

    @Published var book: Book? = nil
    @Published var totalProgression: Double? = nil
    @Published var otherBooksByAuthor: [HomeBook] = []
    @Published var isLoading = true

    private let bookID: UUID
    private let bookRepository: BookRepository

    init(bookID: UUID, bookRepository: BookRepository) {
        self.bookID = bookID
        self.bookRepository = bookRepository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let books = await bookRepository.listBooks()
        book = books.first { $0.id == bookID }

        if let loc = ReadingStateStore.shared.loadLocator(forBookID: bookID) {
            totalProgression = loc.locations.totalProgression
        }

        if let author = book?.author, !author.isEmpty {
            otherBooksByAuthor =
                books
                .filter { $0.id != bookID && $0.author == author }
                .map { HomeViewModel.makeHomeBook($0) }
        }
    }

    var pageCountText: String {
        guard let n = book?.estimatedPageCount else { return "—" }
        return "\(n)"
    }

    var readingTimeText: String {
        guard let mins = book?.estimatedReadingTimeMinutes else { return "—" }
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var progressText: String {
        guard let p = totalProgression else { return "—" }
        return "\(Int(p * 100))%"
    }
}