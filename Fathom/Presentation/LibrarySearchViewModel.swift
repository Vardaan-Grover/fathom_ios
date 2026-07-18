import Combine
import SwiftUI

/// Drives the library search field and its results grid.
///
/// Search runs against the `books_fts` index rather than filtering an in-memory
/// array, so cost tracks the number of matches instead of the size of the
/// library. That means no debounce: every keystroke issues a query immediately,
/// and the previous one is cancelled if it's still in flight.
@MainActor
final class LibrarySearchViewModel: ObservableObject {

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            search()
        }
    }

    /// True while the search surface is open (field focused or query present).
    @Published var isActive: Bool = false

    /// Books to show in the grid. While the query is empty this is the whole
    /// library, so the surface is a browsing view as much as a search view.
    @Published private(set) var results: [HomeBook] = []

    /// The unfiltered library, kept in sync from HomeViewModel.
    private var allBooks: [HomeBook] = []
    private var booksByID: [UUID: HomeBook] = [:]

    private let bookRepository: BookRepository
    private var searchTask: Task<Void, Never>?

    init(bookRepository: BookRepository) {
        self.bookRepository = bookRepository
    }

    /// Called whenever HomeViewModel reloads, so the empty-query grid and the
    /// ID→HomeBook mapping stay current.
    func updateLibrary(_ books: [HomeBook]) {
        allBooks = books
        booksByID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if !hasQuery { results = books }
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A query was typed but nothing matched — distinct from "not searching yet".
    var isEmptyResult: Bool {
        hasQuery && results.isEmpty
    }

    func open() {
        isActive = true
        results = allBooks
    }

    func close() {
        searchTask?.cancel()
        searchTask = nil
        isActive = false
        query = ""
        results = allBooks
    }

    private func search() {
        // Supersede any query still running — results must reflect the latest
        // keystroke, not whichever query happens to finish last.
        searchTask?.cancel()

        guard hasQuery else {
            searchTask = nil
            results = allBooks
            return
        }

        let query = self.query
        searchTask = Task { [weak self] in
            guard let self else { return }
            let matches = await bookRepository.searchBooks(query: query)
            guard !Task.isCancelled else { return }

            // Map back to HomeBook (which carries cover art and shelf
            // membership for the context menus), preserving the bm25 ranking.
            let ranked = matches.compactMap { self.booksByID[$0.id] }
            guard !Task.isCancelled else { return }
            self.results = ranked
        }
    }
}
