import Foundation

final class AppContainer {
    // Repos
    let bookRepo: BookRepository
    let databaseManager: DatabaseManager
    
    // Services
    let readerService: ReaderService
    let preprocessingCoordinator: BookPreprocessingCoordinator
    
    // AI + Context will be wired soon
    let contextEngine: ContextEngine
    let aiClient: AIClient
    
    private init(
        databaseManager: DatabaseManager,
        bookRepo: BookRepository,
        readerService: ReaderService,
        preprocessingCoordinator: BookPreprocessingCoordinator,
        contextEngine: ContextEngine,
        aiClient: AIClient
    ) {
        self.databaseManager = databaseManager
        self.bookRepo = bookRepo
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

        let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let openAIModel = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-4.1"
        let geminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]

        let bookRepo = BookRepositorySQLite(dbQueue: databaseManager.dbQueue)
        let readerService = DefaultReaderService()
        let coordinator = BookPreprocessingCoordinator(
            dbQueue: databaseManager.dbQueue,
            geminiAPIKey: geminiKey
        )
        let contextEngine = DefaultContextEngine()

        let aiClient: AIClient
        if let key = openAIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            aiClient = OpenAIClient(apiKey: key, model: openAIModel)
        } else {
            aiClient = MockAIClient()
        }
        
        return AppContainer(
            databaseManager: databaseManager,
            bookRepo: bookRepo,
            readerService: readerService,
            preprocessingCoordinator: coordinator,
            contextEngine: contextEngine,
            aiClient: aiClient
        )
    }
}
