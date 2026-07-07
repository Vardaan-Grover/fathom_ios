import Foundation

final class AppContainer {
    /// The app-wide object graph. Prefer constructor injection from here;
    /// reach for `AppContainer.shared` directly only where SwiftUI view
    /// construction makes threading a dependency through impractical.
    static let shared = AppContainer.live()

    // Repos
    let bookRepo: BookRepository
    let categoryRepo: CategoryRepository
    let vocabularyRepo: VocabularyRepository
    let databaseManager: DatabaseManager

    // Services
    let readerService: ReaderService
    let preprocessingCoordinator: BookPreprocessingCoordinator

    let contextEngine: ContextEngine
    let aiClient: AIClient

    private init(
        databaseManager: DatabaseManager,
        bookRepo: BookRepository,
        categoryRepo: CategoryRepository,
        vocabularyRepo: VocabularyRepository,
        readerService: ReaderService,
        preprocessingCoordinator: BookPreprocessingCoordinator,
        contextEngine: ContextEngine,
        aiClient: AIClient
    ) {
        self.databaseManager = databaseManager
        self.bookRepo = bookRepo
        self.categoryRepo = categoryRepo
        self.vocabularyRepo = vocabularyRepo
        self.readerService = readerService
        self.preprocessingCoordinator = preprocessingCoordinator
        self.contextEngine = contextEngine
        self.aiClient = aiClient
    }

    static func live() -> AppContainer {
        let databaseManager = DatabaseManager.shared

        do {
            try databaseManager.runStartupSmokeTest()
        } catch {
            assertionFailure("Database smoke test failed: \(error)")
        }

        let bookRepo = BookRepositorySQLite(dbQueue: databaseManager.dbQueue)
        let categoryRepo = CategoryRepositorySQLite(dbQueue: databaseManager.dbQueue)
        let vocabularyRepo = VocabularyRepositorySQLite(dbQueue: databaseManager.dbQueue)
        let readerService = DefaultReaderService()
        let coordinator = BookPreprocessingCoordinator(
            dbQueue: databaseManager.dbQueue
        )
        let contextEngine = DefaultContextEngine()

        let aiClient = BackendAIClient()

        return AppContainer(
            databaseManager: databaseManager,
            bookRepo: bookRepo,
            categoryRepo: categoryRepo,
            vocabularyRepo: vocabularyRepo,
            readerService: readerService,
            preprocessingCoordinator: coordinator,
            contextEngine: contextEngine,
            aiClient: aiClient
        )
    }
}
