import SwiftUI

@main
struct ReadoraApp: App {
    
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            LibraryView(
                viewModel: LibraryViewModel(
                    bookRepo: container.bookRepo,
                    readerService: container.readerService,
                    contextEngine: container.contextEngine,
                    aiClient: container.aiClient,
                    preprocessingCoordinator: container.preprocessingCoordinator
                )
            )
        }
    }
}

#Preview {
    let container = AppContainer.live()
    
            LibraryView(
                viewModel: LibraryViewModel(
                    bookRepo: container.bookRepo,
                    readerService: container.readerService,
                    contextEngine: container.contextEngine,
                    aiClient: container.aiClient,
                    preprocessingCoordinator: container.preprocessingCoordinator
                )
            )
}
