import SwiftUI

@main
struct FathomApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authService = AuthService()
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var themeManager = ThemeManager()

    private let bookRepository: BookRepository
    private let vocabularyRepo: VocabularyRepository

    init() {
        let container = AppContainer.shared
        bookRepository = container.bookRepo
        vocabularyRepo = container.vocabularyRepo
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            bookRepository: container.bookRepo,
            categoryRepository: container.categoryRepo
        ))
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(
            bookRepo: container.bookRepo,
            preprocessingCoordinator: container.preprocessingCoordinator
        ))
    }

    var body: some Scene {
        WindowGroup {
            ToastRootView {
                AuthFlowView(
                    homeViewModel: homeViewModel,
                    libraryViewModel: libraryViewModel,
                    bookRepository: bookRepository,
                    vocabularyRepo: vocabularyRepo
                )
                .environmentObject(authService)
                .environmentObject(themeManager)
                .task { await authService.startListening() }
                // Storage + CloudKit come up independently of any Fathom
                // account — both are scoped by Apple ID.
                .task { await SyncBootstrap.start() }
                .task { await homeViewModel.load() }
                .onOpenURL { url in
                    if url.isFileURL && url.pathExtension.lowercased() == "epub" {
                        libraryViewModel.handleIncomingEPUB(url)
                    } else {
                        Task { try? await authService.handleDeepLink(url) }
                    }
                }
                .themed(with: themeManager)
                // Pull remote changes whenever the app comes to the foreground.
                // SyncEngine guards internally if not started (no iCloud/paid account).
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await SyncEngine.shared.fetchChangesIfNeeded() }
                    } else {
                        // Positions and settings are disk-written on a debounce;
                        // force the pending writes out before we can be killed.
                        ReadingStateStore.shared.flush()
                        ReaderSettingsStore.shared.flush()
                    }
                }
            }
        }
    }
}
