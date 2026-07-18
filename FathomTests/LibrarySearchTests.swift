import Foundation
import GRDB
import Testing

@testable import Fathom

/// Exercises the library search path end to end: the query grammar in
/// `LibrarySearch`, and the `books_fts` index and triggers from migration v28
/// running against a real (in-memory) SQLite database.
struct LibrarySearchTests {

    // MARK: - Query grammar

    @Test func emptyAndPunctuationOnlyQueriesProduceNoExpression() {
        #expect(LibrarySearch.matchExpression(for: "") == nil)
        #expect(LibrarySearch.matchExpression(for: "   ") == nil)
        #expect(LibrarySearch.matchExpression(for: "   ***  ") == nil)
        #expect(LibrarySearch.matchExpression(for: "\"") == nil)
    }

    @Test func everyTokenIsQuotedAndPrefixMatched() {
        #expect(LibrarySearch.matchExpression(for: "atomic") == "\"atomic\"*")
        #expect(LibrarySearch.matchExpression(for: "clear atom") == "\"clear\"* \"atom\"*")
    }

    /// FTS5 operators typed by a user are data, not syntax. If any of these
    /// reached the parser unescaped the query would either throw or silently
    /// mean something else.
    @Test func ftsOperatorsInQueryAreNeverTreatedAsSyntax() {
        #expect(LibrarySearch.matchExpression(for: "\"quoted\"") == "\"quoted\"*")
        #expect(LibrarySearch.matchExpression(for: "a OR b") == "\"a\"* \"OR\"* \"b\"*")
        #expect(LibrarySearch.matchExpression(for: "foo-bar") == "\"foo\"* \"bar\"*")
        #expect(LibrarySearch.matchExpression(for: "col:val") == "\"col\"* \"val\"*")
        #expect(LibrarySearch.matchExpression(for: "NEAR(a b)") == "\"NEAR\"* \"a\"* \"b\"*")
    }

    // MARK: - Index behaviour

    private func makeRepo(_ books: [Book]) async throws -> (BookRepositorySQLite, DatabaseQueue) {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        let repo = BookRepositorySQLite(dbQueue: dbQueue)
        for book in books { await repo.addBook(book) }
        return (repo, dbQueue)
    }

    private func book(_ title: String, _ author: String?, _ description: String? = nil) -> Book {
        var b = Book(id: UUID(), title: title, author: author, format: .epub, localFilename: nil)
        b.description = description
        return b
    }

    @Test func findsByTitleAuthorAndDescription() async throws {
        let (repo, _) = try await makeRepo([
            book("Atomic Habits", "James Clear", "An easy and proven way to build good habits"),
            book("The Book of Five Rings", "Miyamoto Musashi", "A treatise on strategy"),
        ])

        #expect(await repo.searchBooks(query: "atomic").map(\.title) == ["Atomic Habits"])
        #expect(await repo.searchBooks(query: "musashi").map(\.title) == ["The Book of Five Rings"])
        #expect(await repo.searchBooks(query: "treatise").map(\.title) == ["The Book of Five Rings"])
    }

    @Test func tokensAreAndedAndMayMatchDifferentColumns() async throws {
        let (repo, _) = try await makeRepo([
            book("Atomic Habits", "James Clear"),
            book("Atomic Physics", "Niels Bohr"),
        ])
        // "clear" hits the author, "atom" hits the title — both must match.
        #expect(await repo.searchBooks(query: "clear atom").map(\.title) == ["Atomic Habits"])
        #expect(await repo.searchBooks(query: "atomic").count == 2)
        #expect(await repo.searchBooks(query: "atomic nonexistent").isEmpty)
    }

    /// The reason for prefix='2 3' — search runs while the user is mid-word.
    @Test func partialWordsMatchAsTheUserTypes() async throws {
        let (repo, _) = try await makeRepo([book("Atomic Habits", "James Clear")])
        for partial in ["at", "ato", "atom", "atomi", "atomic"] {
            #expect(await repo.searchBooks(query: partial).count == 1, "failed on '\(partial)'")
        }
    }

    /// remove_diacritics 2 folds the index; the query layer folds nothing.
    @Test func accentsAreFoldedInBothDirections() async throws {
        let (repo, _) = try await makeRepo([book("Wuthering Heights", "Emily Brontë")])
        #expect(await repo.searchBooks(query: "bronte").count == 1)
        #expect(await repo.searchBooks(query: "Brontë").count == 1)
        #expect(await repo.searchBooks(query: "BRONTE").count == 1)
    }

    @Test func titleMatchesOutrankDescriptionMatches() async throws {
        let (repo, _) = try await makeRepo([
            book("A History of Reading", "Alberto Manguel", "Mentions strategy in passing"),
            book("Strategy", "Lawrence Freedman", "A history"),
        ])
        // bm25 weights title 10x over description, so the title hit leads.
        #expect(await repo.searchBooks(query: "strategy").first?.title == "Strategy")
    }

    @Test func emptyQueryReturnsNothingRatherThanEverything() async throws {
        let (repo, _) = try await makeRepo([book("Atomic Habits", "James Clear")])
        #expect(await repo.searchBooks(query: "").isEmpty)
        #expect(await repo.searchBooks(query: "  ").isEmpty)
    }

    /// A user typing punctuation must never produce an FTS5 syntax error —
    /// this would throw and log rather than return [] if quoting were wrong.
    @Test func punctuationHeavyQueriesDoNotThrow() async throws {
        let (repo, _) = try await makeRepo([book("Atomic Habits", "James Clear")])
        for query in ["\"", "*", "a*", "()", "NEAR(", "foo:", "-x", "\"unbalanced"] {
            _ = await repo.searchBooks(query: query)  // must not throw
        }
        #expect(await repo.searchBooks(query: "atomic").count == 1)  // index still healthy
    }

    // MARK: - Trigger sync

    @Test func indexTracksInsertsUpdatesAndDeletes() async throws {
        let (repo, _) = try await makeRepo([])

        var b = book("Original Title", "Some Author")
        await repo.addBook(b)
        #expect(await repo.searchBooks(query: "original").count == 1)

        b.title = "Renamed Title"
        await repo.updateBook(b)
        #expect(await repo.searchBooks(query: "renamed").count == 1)
        #expect(await repo.searchBooks(query: "original").isEmpty, "stale title still indexed")

        await repo.deleteBook(b)
        #expect(await repo.searchBooks(query: "renamed").isEmpty)
    }

    /// External-content FTS5 corrupts silently if the delete trigger passes the
    /// wrong column values, and the damage only surfaces later. `integrity-check`
    /// is what actually catches it.
    @Test func indexStaysConsistentAfterChurn() async throws {
        let (repo, dbQueue) = try await makeRepo([])

        var books = (0..<50).map { book("Book Number \($0)", "Author \($0)", "Description \($0)") }
        for b in books { await repo.addBook(b) }
        for i in 0..<50 where i % 3 == 0 {
            books[i].title = "Updated Book \(i)"
            await repo.updateBook(books[i])
        }
        for i in 0..<50 where i % 5 == 0 {
            await repo.deleteBook(books[i])
        }

        // integrity-check is a write command despite only verifying.
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO books_fts(books_fts) VALUES('integrity-check')")
        }

        // 0 and 15/30/45 were both updated and deleted; 5,10,20,... deleted only.
        #expect(await repo.searchBooks(query: "Updated").count == 13)
        #expect(await repo.searchBooks(query: "Book").count == 40)
    }

    /// A book deleted via raw SQL (as the CloudKit pull path does) must still
    /// leave the index clean — the trigger is the only thing keeping it so.
    @Test func rawSQLDeleteKeepsIndexConsistent() async throws {
        let (repo, dbQueue) = try await makeRepo([book("Ghost Book", "Nobody")])
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM books WHERE title = 'Ghost Book'")
        }
        // integrity-check is a write command despite only verifying.
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO books_fts(books_fts) VALUES('integrity-check')")
        }
        #expect(await repo.searchBooks(query: "ghost").isEmpty)
    }
}
