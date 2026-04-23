import Combine
import CryptoKit
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published private(set) var books: [Book] = []
    @Published var isLoading = false

    private let bookRepo: BookRepository
    private let readerService: ReaderService
    private let contextEngine: ContextEngine
    private let aiClient: AIClient
    private let preprocessingCoordinator: BookPreprocessingCoordinator

    init(
        bookRepo: BookRepository,
        readerService: ReaderService,
        contextEngine: ContextEngine,
        aiClient: AIClient,
        preprocessingCoordinator: BookPreprocessingCoordinator
    ) {
        self.bookRepo = bookRepo
        self.readerService = readerService
        self.contextEngine = contextEngine
        self.aiClient = aiClient
        self.preprocessingCoordinator = preprocessingCoordinator
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        books = await bookRepo.listBooks()
        await resumePreprocessingIfNeeded(for: books)
    }

    private func resumePreprocessingIfNeeded(for books: [Book]) async {
        for book in books {
            let indexed = await NarrativeContextStore.shared.hasParagraphs(for: book.id)
            guard !indexed else { continue }
            AppLogger.log(tag: "LibraryViewModel", "⚠️ \(book.title) has no local paragraphs — resuming preprocessing")
            Task.detached { [preprocessingCoordinator] in
                await preprocessingCoordinator.preprocess(book: book)
            }
        }
    }

    func openBook(_ book: Book) async -> ReaderViewModel {
        let passage = await readerService.openSamplePassage(for: book)

        return ReaderViewModel(
            passage: passage,
            contextEngine: contextEngine,
            aiClient: aiClient
        )
    }

    func importBook(from url: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // For fileImporter URLs, use security scope
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let localURL = try BookFileStore.copyIntoAppLibrary(from: url)

            AppLogger.log(tag: "LibraryViewModel", "1. Extracting EPUB metadata...")
            let meta = try await EPUBMetadataExtractor.extract(from: localURL)
            AppLogger.log(tag: "LibraryViewModel", "   Title: \(meta.title), Author: \(meta.author ?? "nil"), Language: \(meta.language ?? "nil")")

            var coverFilename: String? = nil
            if let coverData = meta.coverImageData {
                let coverID = UUID()
                coverFilename = try BookFileStore.saveCoverImage(coverData, coverID: coverID)
                AppLogger.log(tag: "LibraryViewModel", "   Cover saved: \(coverFilename!)")
            }

            let backendService = BackendService.shared

            AppLogger.log(tag: "LibraryViewModel", "2. Requesting upload URL for \(meta.title)...")
            let uploadInfo = try await backendService.getUploadURL(
                filename: localURL.lastPathComponent)

            AppLogger.log(tag: "LibraryViewModel", "3. Computing SHA-256 hash of EPUB bytes...")
            let fileData = try Data(contentsOf: localURL)
            let hashDigest = SHA256.hash(data: fileData)
            let hashString = hashDigest.compactMap { String(format: "%02x", $0) }.joined()

            AppLogger.log(
                tag: "LibraryViewModel", "4. Initializing book record with hash: \(hashString)")
            let backendBookResponse = try await backendService.initBook(
                s3Key: uploadInfo.s3_key,
                title: meta.title,
                author: meta.author,
                language: meta.language,
                contentHash: hashString
            )

            // If duplicate, SKIP R2 upload & ingestion trigger
            if !backendBookResponse.duplicate {
                AppLogger.log(
                    tag: "LibraryViewModel", "5. New book detected. Uploading EPUB to R2...")
                try await backendService.uploadEPUB(
                    uploadURL: uploadInfo.upload_url, fileURL: localURL)

                AppLogger.log(
                    tag: "LibraryViewModel", "6. Triggering ingestion worker on Backend...")
                try await backendService.startIngestion(bookID: backendBookResponse.book_id)
            } else {
                AppLogger.log(
                    tag: "LibraryViewModel",
                    "5 & 6. Duplicate detected. Skipping R2 upload and ingestion.")
            }

            let book = Book(
                id: backendBookResponse.book_id,
                title: meta.title,
                author: meta.author,
                format: .epub,
                localFilename: localURL.lastPathComponent,
                description: meta.description,
                language: meta.language,
                publisher: meta.publisher,
                coverFilename: coverFilename
            )

            AppLogger.log(tag: "LibraryViewModel", "Saving \(meta.title) to local database.")
            await bookRepo.addBook(book)
            books = await bookRepo.listBooks()

            AppLogger.log(
                tag: "LibraryViewModel",
                "Firing off BookPreprocessingCoordinator for index generation.")
            Task.detached {
                await self.preprocessingCoordinator.preprocess(book: book)
            }
        } catch {
            AppLogger.logError(tag: "LibraryViewModel", error)
        }
    }

    func deleteBooks(at offsets: IndexSet) async {
        let booksToDelete = offsets.map { books[$0] }

        for book in booksToDelete {
            // 1. Delete physical file if it exists
            if let url = book.localURL {
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                        AppLogger.log(
                            tag: "LibraryViewModel", "Deleted exact local file at \(url.path)")
                    }
                } catch {
                    AppLogger.logError(tag: "LibraryViewModel", error)
                }
            }

            // 2. Remove from repository (database)
            await bookRepo.deleteBook(book)
        }

        // 3. Refresh list
        books = await bookRepo.listBooks()
    }
}
