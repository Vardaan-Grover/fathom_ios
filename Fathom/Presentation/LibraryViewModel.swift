import Combine
import CryptoKit
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published private(set) var books: [Book] = []
    @Published var isLoading = false
    @Published var pendingCustomization: BookCustomization? = nil
    @Published var pendingIncomingURL: URL? = nil

    private var importContinuation: CheckedContinuation<BookCustomization, Error>?
    private var pendingLocalURL: URL?

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

    enum ImportError: Error, LocalizedError {
        case duplicateBook
        
        var errorDescription: String? {
            switch self {
            case .duplicateBook:
                return "This book is already in your library."
            }
        }
    }

    func importBook(from url: URL) async throws {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            isLoading = true
            
            // Check for duplicate book early by hashing the incoming file directly
            let hashString = try await Task.detached {
                let fileData = try Data(contentsOf: url)
                let hashDigest = SHA256.hash(data: fileData)
                return hashDigest.compactMap { String(format: "%02x", $0) }.joined()
            }.value
            // Fetch all books dynamically to ensure we aren't checking a stale/unloaded in-memory array
            let allBooks = await bookRepo.listBooks()
            if allBooks.contains(where: { $0.contentHash == hashString }) {
                isLoading = false
                throw ImportError.duplicateBook
            }

            let localURL = try BookFileStore.copyIntoAppLibrary(from: url)
            pendingLocalURL = localURL

            AppLogger.log(tag: "LibraryViewModel", "1. Extracting EPUB metadata...")
            let meta = try await EPUBMetadataExtractor.extract(from: localURL)
            AppLogger.log(tag: "LibraryViewModel", "   Title: \(meta.title), Author: \(meta.author ?? "nil"), Language: \(meta.language ?? "nil")")
            isLoading = false

            // Show the customization sheet and wait for the user to confirm or cancel.
            // Original EPUB metadata is preserved so the backend always receives what
            // the file actually contains.
            let placeholderID = UUID()
            let customization = BookCustomization(
                id: placeholderID,
                title: meta.title,
                author: meta.author ?? "",
                description: meta.description ?? "",
                coverImageData: meta.coverImageData,
                originalTitle: meta.title,
                originalAuthor: meta.author,
                originalLanguage: meta.language
            )

            AppLogger.log(tag: "LibraryViewModel", "2. Awaiting user customization...")
            let finalCustomization = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<BookCustomization, Error>) in
                importContinuation = cont
                pendingCustomization = customization
            }
            pendingCustomization = nil
            pendingLocalURL = nil

            let aiEnabled = finalCustomization.enableAI
            AppLogger.log(tag: "LibraryViewModel", "   AI enabled: \(aiEnabled)")

            isLoading = true
            defer { isLoading = false }

            // Cover is saved here, after user may have swapped it.
            var coverFilename: String? = nil
            if let coverData = finalCustomization.coverImageData {
                let coverID = UUID()
                coverFilename = try BookFileStore.saveCoverImage(coverData, coverID: coverID)
                AppLogger.log(tag: "LibraryViewModel", "   Cover saved: \(coverFilename!)")
            }

            var book = Book(
                id: finalCustomization.id,  // reuse the preview UUID so palette colour is consistent
                title: finalCustomization.title,
                author: finalCustomization.author.isEmpty ? nil : finalCustomization.author,
                format: .epub,
                localFilename: localURL.lastPathComponent,
                description: finalCustomization.description.isEmpty ? nil : finalCustomization.description,
                language: meta.language,
                publisher: meta.publisher,
                coverFilename: coverFilename
            )
            book.contentHash = hashString

            if !aiEnabled {
                // Flow A: Just Read — store locally, no backend calls.
                AppLogger.log(tag: "LibraryViewModel", "Flow A: Storing book locally, no backend.")
                book.aiEnabled = false
                book.backendBookID = nil
                book.preprocessingStatus = .pending
            } else {
                // Flow B: Enable AI — upload to R2, register with backend, branch on response.
                let backendService = BackendService.shared

                AppLogger.log(tag: "LibraryViewModel", "Flow B: Requesting upload URL...")
                let uploadInfo = try await backendService.getUploadURL(filename: localURL.lastPathComponent)

                AppLogger.log(tag: "LibraryViewModel", "Initializing book record on backend...")
                // Backend always receives original EPUB metadata — user edits are local-only.
                let backendBookResponse = try await backendService.initBook(
                    s3Key: uploadInfo.s3_key,
                    title: finalCustomization.originalTitle,
                    author: finalCustomization.originalAuthor,
                    language: finalCustomization.originalLanguage,
                    contentHash: hashString
                )

                book.aiEnabled = true
                book.backendBookID = backendBookResponse.book_id

                if backendBookResponse.duplicate {
                    switch backendBookResponse.status {
                    case "ready":
                        // Branch 1: duplicate + ready → AI immediately available.
                        AppLogger.log(tag: "LibraryViewModel", "Branch 1: duplicate + ready. Skipping upload and ingestion.")
                        book.preprocessingStatus = .completed
                    case "failed":
                        // Branch 4: duplicate + failed → re-trigger ingestion, file already in R2.
                        AppLogger.log(tag: "LibraryViewModel", "Branch 4: duplicate + failed. Re-triggering ingestion.")
                        try await backendService.startIngestion(bookID: backendBookResponse.book_id)
                        book.preprocessingStatus = .inProgress
                    default:
                        // Branch 2: duplicate + processing/pending → already enqueued, just poll.
                        AppLogger.log(tag: "LibraryViewModel", "Branch 2: duplicate + \(backendBookResponse.status). Polling will begin.")
                        book.preprocessingStatus = .inProgress
                    }
                } else {
                    // Branch 3: new book → upload to R2, trigger ingestion.
                    AppLogger.log(tag: "LibraryViewModel", "Branch 3: new book. Uploading EPUB to R2...")
                    try await backendService.uploadEPUB(uploadURL: uploadInfo.upload_url, fileURL: localURL)
                    AppLogger.log(tag: "LibraryViewModel", "Triggering ingestion...")
                    try await backendService.startIngestion(bookID: backendBookResponse.book_id)
                    book.preprocessingStatus = .inProgress
                }
            }

            AppLogger.log(tag: "LibraryViewModel", "Saving \(book.title) to local database.")
            await bookRepo.addBook(book)
            books = await bookRepo.listBooks()

            AppLogger.log(tag: "LibraryViewModel", "Firing off BookPreprocessingCoordinator for index generation.")
            Task.detached {
                await self.preprocessingCoordinator.preprocess(book: book)
            }
        } catch is CancellationError {
            isLoading = false
            AppLogger.log(tag: "LibraryViewModel", "Import cancelled by user.")
        } catch {
            isLoading = false
            AppLogger.logError(tag: "LibraryViewModel", error)
            throw error
        }
    }

    func confirmImport(with customization: BookCustomization) {
        importContinuation?.resume(returning: customization)
        importContinuation = nil
    }

    func handleIncomingEPUB(_ url: URL) {
        pendingIncomingURL = url
    }

    func cancelImport() {
        if let url = pendingLocalURL {
            try? FileManager.default.removeItem(at: url)
            AppLogger.log(tag: "LibraryViewModel", "Import cancelled — removed temp file at \(url.lastPathComponent).")
        }
        importContinuation?.resume(throwing: CancellationError())
        importContinuation = nil
        pendingCustomization = nil
        pendingLocalURL = nil
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
