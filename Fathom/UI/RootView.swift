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
    @State private var showShelfSheet = false
    
    @Environment(\.showToast) private var showToast

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
                SettingsView()
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
                do {
                    try await libraryViewModel.importBook(from: url)
                    await homeViewModel.load()
                } catch {
                    if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
                        showToast(Toast(title: message, duration: 3, placementOffset: -72, symbol: "exclamationmark.triangle"))
                    } else {
                        showToast(Toast(title: "Failed to import book", duration: 3, placementOffset: -72, symbol: "exclamationmark.triangle"))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            customTabBar
                .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showShelfSheet) {
            NewShelfSheet { name, colorHex in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    homeViewModel.createCategory(name: name, colorHex: colorHex)
                }
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $libraryViewModel.pendingCustomization) { customization in
            BookCustomizationSheet(
                initial: customization,
                onConfirm: { edited in libraryViewModel.confirmImport(with: edited) },
                onCancel: { libraryViewModel.cancelImport() }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
