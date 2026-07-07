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
    let preprocessingCoordinator: BookPreprocessingCoordinator

    private init(
        databaseManager: DatabaseManager,
        bookRepo: BookRepository,
        categoryRepo: CategoryRepository,
        vocabularyRepo: VocabularyRepository,
        preprocessingCoordinator: BookPreprocessingCoordinator
    ) {
        self.databaseManager = databaseManager
        self.bookRepo = bookRepo
        self.categoryRepo = categoryRepo
        self.vocabularyRepo = vocabularyRepo
        self.preprocessingCoordinator = preprocessingCoordinator
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
        let coordinator = BookPreprocessingCoordinator(
            dbQueue: databaseManager.dbQueue
        )

        return AppContainer(
            databaseManager: databaseManager,
            bookRepo: bookRepo,
            categoryRepo: categoryRepo,
            vocabularyRepo: vocabularyRepo,
            preprocessingCoordinator: coordinator
        )
    }
}
