import SwiftUI

@main
struct FathomApp: App {
    @StateObject private var authService = AuthService()
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var themeManager = ThemeManager()

    private let bookRepository: BookRepository

    init() {
        let container = AppContainer.live()
        bookRepository = container.bookRepo
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            bookRepository: container.bookRepo,
            categoryRepository: container.categoryRepo
        ))
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
            AuthFlowView(
                homeViewModel: homeViewModel,
                libraryViewModel: libraryViewModel,
                bookRepository: bookRepository
            )
            .environmentObject(authService)
            .task { await authService.startListening() }
            .task { await homeViewModel.load() }
            .onOpenURL { url in
                Task { try? await authService.handleDeepLink(url) }
            }
            .themed(with: themeManager)
        }
    }
}
