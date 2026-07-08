import SwiftUI
import UniformTypeIdentifiers

enum CustomTab: String, CaseIterable {
    case library = "Library"
    case vocabulary = "Vocab"
    case profile = "Profile"

    var symbol: String {
        switch self {
        case .library: return "books.vertical"
        case .vocabulary: return "text.book.closed"
        case .profile: return "person.circle"
        }
    }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

struct RootView: View {
    @ObservedObject var homeViewModel: HomeViewModel
    @ObservedObject var libraryViewModel: LibraryViewModel
    let bookRepository: BookRepository

    @StateObject private var vocabularyTabViewModel: VocabularyTabViewModel

    @State private var activeTab: CustomTab = .library
    @State private var showImporter = false
    @State private var showShelfSheet = false

    @Environment(\.showToast) private var showToast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    
    @AppStorage("fathom.home.viewStyle") private var viewStyle: HomeViewStyle = .glassShelves

    init(
        homeViewModel: HomeViewModel,
        libraryViewModel: LibraryViewModel,
        bookRepository: BookRepository,
        vocabularyRepo: VocabularyRepository
    ) {
        self.homeViewModel = homeViewModel
        self.libraryViewModel = libraryViewModel
        self.bookRepository = bookRepository
        _vocabularyTabViewModel = StateObject(
            wrappedValue: VocabularyTabViewModel(vocabularyRepo: vocabularyRepo)
        )
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            // Base layer: TabView + tab bar blurred together as one unit.
            // No separate per-layer blur — everything underneath the card
            // goes out of focus as a single composite image.
            contentLayer
                .blur(radius: vocabularyTabViewModel.isOverlayVisible ? 3 : 0)
                .allowsHitTesting(!vocabularyTabViewModel.isOverlayVisible)
                .animation(
                    .spring(duration: 0.42, bounce: 0.05),
                    value: vocabularyTabViewModel.isOverlayVisible)

            // Scrim
            if vocabularyTabViewModel.selectedWord != nil {
                Color.black
                    .opacity(vocabularyTabViewModel.isExpanded ? 0.52 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { vocabularyTabViewModel.dismissExpanded() }
                    .allowsHitTesting(vocabularyTabViewModel.isExpanded)
                    .animation(.easeInOut(duration: 0.26), value: vocabularyTabViewModel.isExpanded)
            }

            // Expanded word card — floats above the blurred base layer
            if let word = vocabularyTabViewModel.selectedWord {
                ExpandedWordCard(
                    word: word,
                    accentColor: vocabularyTabViewModel.selectedCardColor,
                    entry: vocabularyTabViewModel.cachedEntry(for: word),
                    sourceFrame: vocabularyTabViewModel.selectedCardFrame,
                    isExpanded: vocabularyTabViewModel.isExpanded,
                    contentVisible: vocabularyTabViewModel.expandedContentVisible,
                    hasPrev: vocabularyTabViewModel.expandedHasPrev,
                    hasNext: vocabularyTabViewModel.expandedHasNext,
                    onDismiss: { vocabularyTabViewModel.dismissExpanded() },
                    onNavigatePrev: { vocabularyTabViewModel.navigateExpanded(by: -1) },
                    onNavigateNext: { vocabularyTabViewModel.navigateExpanded(by: 1) },
                    onDelete: { vocabularyTabViewModel.showDeleteConfirm = true },
                    onShare: { Task { await vocabularyTabViewModel.renderAndShare(word: word) } },
                    onEdit: {
                        vocabularyTabViewModel.wordToEdit = word
                        vocabularyTabViewModel.dismissExpanded()
                    },
                    onJumpToBook: { vocabularyTabViewModel.jumpToBook(word: word) }
                )
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
        }
            
            VStack {
                Spacer()
                customTabBar
                    .padding(.horizontal, 20)
                    .allowsHitTesting(
                        !vocabularyTabViewModel.isCardExpanded
                            && !vocabularyTabViewModel.isSearchFocused
                    )
                    .opacity(vocabularyTabViewModel.isSearchFocused ? 0 : 1)
                    .frame(height: vocabularyTabViewModel.isSearchFocused ? 0 : nil)
                    .animation(
                        .spring(duration: 0.3, bounce: 0.05),
                        value: vocabularyTabViewModel.isSearchFocused)
            }
        }
        .sheet(isPresented: $vocabularyTabViewModel.isShowingShareSheet) {
            if let word = vocabularyTabViewModel.wordToShare {
                WordSharePreviewSheet(
                    word: word,
                    entry: vocabularyTabViewModel.cachedEntry(for: word)
                )
            }
        }
        .confirmationDialog(
            vocabularyTabViewModel.selectedWord.map { "Remove '\($0.word)' from your vocabulary?" }
                ?? "",
            isPresented: $vocabularyTabViewModel.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let word = vocabularyTabViewModel.selectedWord else { return }
                Task {
                    vocabularyTabViewModel.dismissExpanded()
                    await vocabularyTabViewModel.removeWord(word)
                }
            }
        }
        .sheet(isPresented: $showShelfSheet) {
            NewShelfSheet { name, colorHex in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    _ = homeViewModel.createCategory(name: name, colorHex: colorHex)
                }
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $libraryViewModel.pendingCustomization) { customization in
            BookImportFlow(
                initial: customization,
                categories: homeViewModel.categories.filter { !$0.shelfColorHex.isEmpty },
                onCreateShelf: { name, colorHex in
                    homeViewModel.createCategory(name: name, colorHex: colorHex)
                },
                onConfirm: { edited in
                    libraryViewModel.confirmImport(with: edited)
                    for categoryID in edited.selectedCategoryIDs {
                        homeViewModel.toggleBookInCategory(bookID: edited.id, categoryID: categoryID)
                    }
                },
                onCancel: { libraryViewModel.cancelImport() }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vocabularyJumpToBook)) { note in
            guard let bookID = note.userInfo?["bookID"] as? UUID else { return }
            let locatorJSON = note.userInfo?["locatorJSON"] as? String
            activeTab = .library
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(
                    name: .homeScreenOpenReader,
                    object: nil,
                    userInfo: ["bookID": bookID, "locatorJSON": locatorJSON as Any]
                )
            }
        }
        // Handle epubs shared/opened from other apps.
        // Fires both on cold launch (view appears with URL already set) and
        // hot launch (URL arrives while app is running).
        .task {
            if let url = libraryViewModel.pendingIncomingURL {
                handleIncomingFile(url)
            }
        }
        .onChange(of: libraryViewModel.pendingIncomingURL) { _, url in
            guard let url else { return }
            handleIncomingFile(url)
        }
    }

    // All tab screens stay mounted so scroll position and state are preserved,
    // but only the active one is visible/hit-testable.
    private var contentLayer: some View {
        ZStack {
            Group {
                if viewStyle == .classicGrid {
                    ClassicLibraryView(viewModel: homeViewModel, bookRepository: bookRepository)
                } else {
                    HomeScreen(viewModel: homeViewModel, bookRepository: bookRepository)
                }
            }
            .opacity(activeTab == .library ? 1 : 0)
            .allowsHitTesting(activeTab == .library)

            VocabularyTabView(viewModel: vocabularyTabViewModel)
                .opacity(activeTab == .vocabulary ? 1 : 0)
                .allowsHitTesting(activeTab == .vocabulary)

            ProfileView(bookRepository: bookRepository)
                .opacity(activeTab == .profile ? 1 : 0)
                .allowsHitTesting(activeTab == .profile)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.epub],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            Task {
                do {
                    try await libraryViewModel.importBook(from: url)
                    await homeViewModel.load()
                } catch {
                    if let localizedError = error as? LocalizedError,
                        let message = localizedError.errorDescription
                    {
                        showToast(
                            Toast(
                                title: message, duration: 3, placementOffset: -72,
                                symbol: "exclamationmark.triangle"))
                    } else {
                        showToast(
                            Toast(
                                title: "Failed to import book", duration: 3, placementOffset: -72,
                                symbol: "exclamationmark.triangle"))
                    }
                }
            }
        }
    }

    private func handleIncomingFile(_ url: URL) {
        libraryViewModel.pendingIncomingURL = nil
        // Cancel any in-progress import so we can start fresh.
        libraryViewModel.cancelImport()
        activeTab = .library
        NotificationCenter.default.post(name: .dismissReader, object: nil)
        Task {
            // Brief pause so the tab switch and reader dismissal animate before
            // the import sheet appears.
            try? await Task.sleep(nanoseconds: 300_000_000)
            do {
                try await libraryViewModel.importBook(from: url)
                await homeViewModel.load()
                // The system copies the file into the app's Inbox before delivery;
                // once imported we no longer need that copy.
                if url.deletingLastPathComponent().lastPathComponent == "Inbox" {
                    try? FileManager.default.removeItem(at: url)
                }
            } catch is CancellationError {
                // User cancelled the import — nothing to do.
            } catch {
                if let localizedError = error as? LocalizedError,
                   let message = localizedError.errorDescription
                {
                    showToast(
                        Toast(title: message, duration: 3, placementOffset: -72,
                              symbol: "exclamationmark.triangle"))
                } else {
                    showToast(
                        Toast(title: "Failed to import book", duration: 3, placementOffset: -72,
                              symbol: "exclamationmark.triangle"))
                }
            }
        }
    }

    private var customTabBar: some View {
        tabBarContainer
            .frame(height: 60)
    }

    private var tabBarContainer: some View {
        tabBarItems
    }

    private var tabBarItems: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                CustomTabBar(size: proxy.size, activeTab: $activeTab) { tab in
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 24, weight: .bold))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .symbolVariant(.fill)
                    .frame(maxWidth: .infinity)
                }
                .glassCapsule(interactive: true)
            }

            ZStack {
                if activeTab == .vocabulary {
                    Button {
                        vocabularyTabViewModel.showAddWord = true
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                } else {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Add Book", systemImage: "book.badge.plus")
                        }
                        Button {
                            showShelfSheet = true
                        } label: {
                            Label("Add Shelf", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                }

                Group {
                    if activeTab == .vocabulary {
                        AddWordIcon()
                            .transition(
                                reduceMotion
                                    ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .transition(
                                reduceMotion
                                    ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .foregroundColor(.primary)
                .allowsHitTesting(false)
                .animation(.snappy, value: activeTab)
            }
            .frame(width: 60, height: 60)
            .glassCapsule(interactive: true)
        }
    }
}

private struct AddWordIcon: View {
    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "character")
                .font(.system(size: 20, weight: .medium))
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
        }
    }
}
