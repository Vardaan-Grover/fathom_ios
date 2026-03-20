import Foundation
import Combine

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
            // For fileImporter URLs, use security scope
            let accessed = url.startAccessingSecurityScopedResource()
            defer {if accessed {url.stopAccessingSecurityScopedResource()}}
            
            let localURL = try BookFileStore.copyIntoAppLibrary(from: url)
            
            let book = Book(
                id: UUID(),
                title: localURL.deletingPathExtension().lastPathComponent,
                author: nil,
                format: .epub,
                localFilename: localURL.lastPathComponent
            )
            
            await bookRepo.addBook(book)
            print("Book added:", book)
            books = await bookRepo.listBooks()
            print("Books after add:", books)

            Task.detached {
                await self.preprocessingCoordinator.preprocess(book: book)
            }
        } catch {
            // add an error state later
            print("Import failed: \(error)")
        }
    }
}
