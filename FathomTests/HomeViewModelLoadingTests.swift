import Foundation
import Testing

@testable import Fathom

/// The home screen reloads constantly — the sync notification, the scene phase
/// hook, the reader dismissing, a book being finished. What it must never do is
/// take the shelves away while it does so.
@MainActor
struct HomeViewModelLoadingTests {

    private func makeViewModel() -> HomeViewModel {
        HomeViewModel(bookRepository: InMemoryBookRepository(),
                      categoryRepository: InMemoryCategoryRepository())
    }

    @Test("Nothing is claimed before the first load returns")
    func startsWithoutAnAnswer() {
        let viewModel = makeViewModel()

        // Not loaded is not the same as empty. If the empty state keyed off
        // `isLoading` alone it would announce an empty library in the gap
        // before the first read comes back.
        #expect(!viewModel.hasLoaded)
        #expect(!viewModel.isLoading)
    }

    @Test("The first load resolves into a loaded state")
    func firstLoadCompletes() async {
        let viewModel = makeViewModel()
        await viewModel.load()

        #expect(viewModel.hasLoaded)
        #expect(!viewModel.isLoading)
    }

    @Test("A reload never raises the loading indicator")
    func reloadDoesNotBlankTheShelves() async {
        // This is the regression. `load()` used to set `isLoading = true` on
        // entry, so every one of those triggers replaced the shelves with a
        // spinner for the length of a SQLite read — visible as a flicker every
        // time the app was reopened.
        let viewModel = makeViewModel()
        await viewModel.load()

        for _ in 0..<5 {
            await viewModel.load()
            #expect(!viewModel.isLoading)
            #expect(viewModel.hasLoaded)
        }
    }
}
