import SwiftUI
import UniformTypeIdentifiers

enum CustomTab: String, CaseIterable {
    case library = "Library"
    case vocabulary = "Vocab"
    case settings = "Settings"

    var symbol: String {
        switch self {
        case .library: return "books.vertical"
        case .vocabulary: return "text.book.closed"
        case .settings: return "gearshape"
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

    @State private var activeTab: CustomTab = .library
    @State private var showImporter = false

    var body: some View {
        TabView(selection: $activeTab) {
            Tab(value: .library) {
                HomeScreen(viewModel: homeViewModel, bookRepository: bookRepository)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab(value: .vocabulary) {
                Text("Vocabulary")
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab(value: .settings) {
                Text("Settings")
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.epub],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            Task {
                await libraryViewModel.importBook(from: url)
                await homeViewModel.load()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            customTabBar
                .padding(.horizontal, 20)
        }
    }

    private var customTabBar: some View {
        GlassEffectContainer(spacing: 10) {
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
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.primary)
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 60, height: 60)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .frame(height: 60)
    }
}
