import Combine
import CryptoKit
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published private(set) var books: [Book] = []
    @Published var isLoading = false
    @Published var pendingCustomization: BookCustomization? = nil

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

    func importBook(from url: URL) async {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            isLoading = true
            let localURL = try BookFileStore.copyIntoAppLibrary(from: url)
            pendingLocalURL = localURL

            AppLogger.log(tag: "LibraryViewModel", "1. Extracting EPUB metadata...")
            let meta = try await EPUBMetadataExtractor.extract(from: localURL)
            AppLogger.log(tag: "LibraryViewModel", "   Title: \(meta.title), Author: \(meta.author ?? "nil"), Language: \(meta.language ?? "nil")")
            isLoading = false

            // Show the customization sheet and wait for the user to confirm or cancel.
            // Original EPUB metadata is preserved on the struct so the backend always
            // receives what the file actually contains.
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

            isLoading = true
            defer { isLoading = false }

            // Cover is saved here, after user may have swapped it.
            var coverFilename: String? = nil
            if let coverData = finalCustomization.coverImageData {
                let coverID = UUID()
                coverFilename = try BookFileStore.saveCoverImage(coverData, coverID: coverID)
                AppLogger.log(tag: "LibraryViewModel", "   Cover saved: \(coverFilename!)")
            }

            let backendService = BackendService.shared

            AppLogger.log(tag: "LibraryViewModel", "3. Requesting upload URL...")
            let uploadInfo = try await backendService.getUploadURL(
                filename: localURL.lastPathComponent)

            AppLogger.log(tag: "LibraryViewModel", "4. Computing SHA-256 hash of EPUB bytes...")
            let fileData = try Data(contentsOf: localURL)
            let hashDigest = SHA256.hash(data: fileData)
            let hashString = hashDigest.compactMap { String(format: "%02x", $0) }.joined()

            AppLogger.log(tag: "LibraryViewModel", "5. Initializing book record with hash: \(hashString)")
            // Backend always receives the original EPUB metadata — user edits are local-only.
            let backendBookResponse = try await backendService.initBook(
                s3Key: uploadInfo.s3_key,
                title: finalCustomization.originalTitle,
                author: finalCustomization.originalAuthor,
                language: finalCustomization.originalLanguage,
                contentHash: hashString
            )

            if !backendBookResponse.duplicate {
                AppLogger.log(tag: "LibraryViewModel", "6. New book detected. Uploading EPUB to R2...")
                try await backendService.uploadEPUB(
                    uploadURL: uploadInfo.upload_url, fileURL: localURL)

                AppLogger.log(tag: "LibraryViewModel", "7. Triggering ingestion worker on Backend...")
                try await backendService.startIngestion(bookID: backendBookResponse.book_id)
            } else {
                AppLogger.log(
                    tag: "LibraryViewModel",
                    "6 & 7. Duplicate detected. Skipping R2 upload and ingestion.")
            }

            // Local record uses the user's customized title/author/description/cover.
            let book = Book(
                id: backendBookResponse.book_id,
                title: finalCustomization.title,
                author: finalCustomization.author.isEmpty ? nil : finalCustomization.author,
                format: .epub,
                localFilename: localURL.lastPathComponent,
                description: finalCustomization.description.isEmpty ? nil : finalCustomization.description,
                language: meta.language,
                publisher: meta.publisher,
                coverFilename: coverFilename
            )

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
        }
    }

    func confirmImport(with customization: BookCustomization) {
        importContinuation?.resume(returning: customization)
        importContinuation = nil
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
