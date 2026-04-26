import SwiftUI

private struct SelectedBook: Identifiable {
    let id: UUID
}

struct HomeScreen: View {

    @ObservedObject var viewModel: HomeViewModel
    let bookRepository: BookRepository
    @Environment(\.appTheme) var theme

    @State private var selectedBook: SelectedBook? = nil
    @State private var readerBook: Book? = nil
    @State private var editingCategory: HomeCategory? = nil
    @State private var categoryToDelete: HomeCategory? = nil

    // IDs currently in their dissolve-out phase — layout space is released
    // after the dissolve completes, creating a two-phase deletion.
    @State private var removingCategoryIDs: Set<UUID> = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: theme.layout.sectionSpacing) {

                pageHeader
                    .padding(.horizontal, theme.layout.horizontalPadding)
                    .padding(.top, 40)

                Divider()

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 60)
                } else {
                    ForEach(viewModel.categories) { category in
                        let isUserShelf = !category.shelfColorHex.isEmpty
                        let isRemoving = removingCategoryIDs.contains(category.id)

                        BookCategorySection(
                            category: category,
                            onBookTap: { id in selectedBook = SelectedBook(id: id) },
                            onEdit: isUserShelf ? { editingCategory = category } : nil,
                            onDelete: isUserShelf ? { categoryToDelete = category } : nil
                        )
                        // Dissolve modifiers — order matters:
                        // blur first (at natural size), then vertical crush, then fade.
                        .blur(radius: isRemoving ? 8 : 0)
                        .scaleEffect(
                            x: isRemoving ? 0.88 : 1,
                            y: isRemoving ? 0.001 : 1,
                            anchor: .center
                        )
                        .opacity(isRemoving ? 0 : 1)
                        .allowsHitTesting(!isRemoving)
                        // Each section gets an animated transition driven by the
                        // parent withAnimation context on insertion/removal.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
                            removal: .identity // already invisible by the time data removes it
                        ))
                    }
                }
            }
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
        .background(theme.colors.background)
        .sheet(item: $selectedBook) { selection in
            BookDetailsScreen(
                bookID: selection.id,
                bookRepository: bookRepository,
                onStartReading: { book in
                    selectedBook = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        readerBook = book
                    }
                }
            )
            .id(selection.id)
        }
        .sheet(item: $editingCategory) { category in
            NewShelfSheet(
                initialName: category.name,
                initialColorHex: category.shelfColorHex,
                isEditing: true
            ) { name, colorHex in
                // withAnimation drives the name cross-dissolve and shelf band
                // color interpolation simultaneously inside BookCategorySection.
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    viewModel.updateCategory(id: category.id, name: name, colorHex: colorHex)
                }
            }
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
            .presentationBackground(.regularMaterial)
        }
        .confirmationDialog(
            "Delete \"\(categoryToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Shelf", role: .destructive) {
                guard let category = categoryToDelete else { return }
                categoryToDelete = nil
                beginDeleteAnimation(for: category)
            }
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
        } message: {
            Text("This will permanently remove the shelf. Books in it won't be deleted.")
        }
        .fullScreenCover(item: $readerBook) { book in
            if let url = book.localURL {
                ReaderScreen(bookFileURL: url, bookTitle: book.title, bookID: book.id)
            }
        }
    }

    // MARK: - Delete animation

    // Phase 1 (0ms):   blur + vertical crush + fade (~300ms spring)
    // Phase 2 (200ms): layout reflow — remaining items spring upward into the gap.
    // The 200ms overlap makes both phases feel like one continuous motion.
    private func beginDeleteAnimation(for category: HomeCategory) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
            removingCategoryIDs.insert(category.id)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                viewModel.deleteCategory(id: category.id)
            }
            removingCategoryIDs.remove(category.id)
        }
    }

    // MARK: - Page Header
    private var pageHeader: some View {
        VStack(spacing: 0) {
            Text("My Favourite")
                .font(theme.typography.subheadline)
                .foregroundColor(theme.colors.primary)
                .tracking(0.05)
            Text("BOOKS")
                .font(theme.typography.displaySerif)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Preview
#Preview {
    let vm = HomeViewModel(bookRepository: InMemoryBookRepository())
    return HomeScreen(viewModel: vm, bookRepository: InMemoryBookRepository())
        .task { await vm.load() }
}
