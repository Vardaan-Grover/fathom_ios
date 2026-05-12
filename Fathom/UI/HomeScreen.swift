import SwiftUI
import UIKit

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
                    .padding(.horizontal, 20)

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 60)
                } else {
                    if let recentBook = viewModel.recentBook {
                        RecentlyReadTile(
                            book: recentBook,
                            progress: viewModel.recentBookProgress,
                            onTap: {
                                guard let book = viewModel.recentFullBook, book.localURL != nil
                                else { return }
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                readerBook = book
                            }
                        )
                        .padding(.horizontal, 20)
                    }

                    let userShelves = viewModel.categories.filter { !$0.shelfColorHex.isEmpty }

                    ForEach(viewModel.categories) { category in
                        let isUserShelf = !category.shelfColorHex.isEmpty
                        let isRemoving = removingCategoryIDs.contains(category.id)

                        BookCategorySection(
                            category: category,
                            onBookTap: { id in selectedBook = SelectedBook(id: id) },
                            onEdit: isUserShelf
                                ? {
                                    // Delay matches the context menu dismiss animation so the
                                    // edit sheet doesn't fight the blur-out in progress.
                                    let cat = category
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        editingCategory = cat
                                    }
                                } : nil,
                            onDelete: isUserShelf
                                ? {
                                    // Same delay — prevents the confirmation dialog from
                                    // overlapping the context menu's spring dismissal.
                                    let cat = category
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        categoryToDelete = cat
                                    }
                                } : nil,
                            userCategories: userShelves,
                            onToggleCategoryMembership: { bookID, categoryID in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    viewModel.toggleBookInCategory(
                                        bookID: bookID, categoryID: categoryID)
                                }
                            }
                        )
                        // Dissolve modifiers: vertical crush then fade.
                        .scaleEffect(
                            x: isRemoving ? 0.88 : 1,
                            y: isRemoving ? 0.001 : 1,
                            anchor: .center
                        )
                        .opacity(isRemoving ? 0 : 1)
                        .allowsHitTesting(!isRemoving)
                        // Each section gets an animated transition driven by the
                        // parent withAnimation context on insertion/removal.
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(
                                    with: .scale(scale: 0.94, anchor: .top)),
                                removal: .identity  // already invisible by the time data removes it
                            ))
                    }
                }
            }
            .padding(.bottom, 72)
        }
        .background(theme.colors.background)
        .sheet(item: $selectedBook) { selection in
            BookDetailsScreen(
                bookID: selection.id,
                bookRepository: bookRepository,
                onStartReading: { book in
                    selectedBook = nil
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
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
            .padding(.top, 16)
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $categoryToDelete) { category in
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Delete \"\(category.name)\"?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("This will permanently remove the shelf. Books in it won't be deleted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 10)

                HStack(spacing: 12) {
                    Button(role: .cancel) {
                        categoryToDelete = nil
                    } label: {
                        Text("Cancel")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14)
                            )
                            .foregroundStyle(.primary)
                    }
                    Button(role: .destructive) {
                        categoryToDelete = nil
                        beginDeleteAnimation(for: category)
                    } label: {
                        Text("Delete Shelf")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)
                            )
                            .foregroundStyle(.red)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 36)
            .padding(.horizontal, 24)
            .presentationDetents([.height(172)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $readerBook) { book in
            if let url = book.localURL {
                ReaderScreen(
                    bookFileURL: url,
                    bookTitle: book.title,
                    bookID: book.id,
                    backendBookID: book.backendBookID,
                    aiEnabled: book.aiEnabled,
                    ingestionStatus: book.preprocessingStatus,
                    onEnableAI: {
                        readerBook = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            selectedBook = SelectedBook(id: book.id)
                        }
                    }
                )
            }
        }
        .onChange(of: readerBook) { _, newBook in
            if let book = newBook {
                viewModel.recordOpened(book: book)
            } else {
                // Reload after reader dismissal so progress reflects latest position.
                Task { await viewModel.load() }
            }
        }
    }

    // MARK: - Delete animation

    // Phase 1 (0ms):   vertical crush + fade (~300ms spring)
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
