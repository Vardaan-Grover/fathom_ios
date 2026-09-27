import Foundation
import GRDB
import Testing

@testable import Fathom

/// The parts of local-first file storage that do not need a live iCloud
/// container: which files the library references, how placeholders are
/// named, and the per-device "removed download" list.
struct BookFileSyncTests {

    nonisolated private func makeMigratedQueue() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    @Test("Every file a record points at is referenced — EPUB, cover and reflection image")
    func referencedFilesCoverEveryKind() throws {
        let dbQueue = try makeMigratedQueue()
        var book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        book.localFilename = "Cosmos-1.epub"
        book.coverFilename = "cover-1.png"
        let completion = BookCompletion(bookID: book.id, reflectionImageFilename: "reflection-1.jpg",
                                        finishedAt: Date())
        try dbQueue.write { db in
            try book.insert(db)
            try completion.insert(db)
        }

        let refs = try dbQueue.read { db in try BookFileSync.fetchReferenced(db) }

        #expect(refs == [
            BookFileRef(kind: .book, filename: "Cosmos-1.epub"),
            BookFileRef(kind: .cover, filename: "cover-1.png"),
            BookFileRef(kind: .reflection, filename: "reflection-1.jpg")
        ])
    }

    @Test("A book without files references nothing")
    func bookWithoutFilesReferencesNothing() throws {
        let dbQueue = try makeMigratedQueue()
        let book = Book(id: UUID(), title: "Cosmos", author: "Sagan", format: .epub)
        try dbQueue.write { db in try book.insert(db) }

        let refs = try dbQueue.read { db in try BookFileSync.fetchReferenced(db) }
        #expect(refs.isEmpty)
    }

    @Test("A not-yet-downloaded iCloud file is looked for under its placeholder name")
    func placeholderName() {
        let url = URL(fileURLWithPath: "/container/Documents/Books/Cosmos-1.epub")
        let placeholder = ICloudFileStore.shared.placeholderURL(for: url)
        #expect(placeholder.path == "/container/Documents/Books/.Cosmos-1.epub.icloud")
    }

    @Test("Local copies live in Application Support, where iOS never evicts them")
    func localCopiesLiveInApplicationSupport() throws {
        let ref = BookFileRef(kind: .book, filename: "Cosmos-1.epub")
        let url = try #require(ICloudFileStore.shared.localURL(ref))
        #expect(url.deletingLastPathComponent().lastPathComponent == "Books")
        #expect(url.path.contains("Application Support"))
    }

    @Test("A removed book is remembered until it is downloaded again")
    func offloadedListRoundTrips() {
        let filename = "probe-\(UUID().uuidString).epub"
        defer { BookFileSync.forgetOffloaded([BookFileRef(kind: .book, filename: filename)]) }

        #expect(!BookFileSync.isOffloaded(filename))
        BookFileSync.markOffloaded(filename)
        #expect(BookFileSync.isOffloaded(filename))
        BookFileSync.clearOffloaded(filename)
        #expect(!BookFileSync.isOffloaded(filename))
    }
}
