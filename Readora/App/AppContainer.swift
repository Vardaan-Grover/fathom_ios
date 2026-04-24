import Foundation

final class AppContainer {
    // Repos
    let bookRepo: BookRepository
    let categoryRepo: CategoryRepository
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
        readerService: ReaderService,
        preprocessingCoordinator: BookPreprocessingCoordinator,
        contextEngine: ContextEngine,
        aiClient: AIClient
    ) {
        self.databaseManager = databaseManager
        self.bookRepo = bookRepo
        self.categoryRepo = categoryRepo
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
            readerService: readerService,
            preprocessingCoordinator: coordinator,
            contextEngine: contextEngine,
            aiClient: aiClient
        )
    }
}
