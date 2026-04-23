import SwiftUI

@main
struct ReadoraApp: App {
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var themeManager = ThemeManager()

    private let bookRepository: BookRepository

    init() {
        let container = AppContainer.live()
        bookRepository = container.bookRepo
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(bookRepository: container.bookRepo))
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(
            bookRepo: container.bookRepo,
            readerService: container.readerService,
            contextEngine: container.contextEngine,
            aiClient: container.aiClient,
            preprocessingCoordinator: container.preprocessingCoordinator
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                homeViewModel: homeViewModel,
                libraryViewModel: libraryViewModel,
                bookRepository: bookRepository
            )
            .task { await homeViewModel.load() }
            .themed(with: themeManager)  // ← Injects \.appTheme + preferredColorScheme
        }
    }
}
