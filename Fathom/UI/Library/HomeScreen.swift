import SwiftUI
import UIKit

private struct SelectedBook: Identifiable {
    let id: UUID
}

struct HomeScreen: View {

    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject private var downloadMonitor = ICloudDownloadMonitor.shared
    let bookRepository: BookRepository
    @Environment(\.appTheme) var theme

    @State private var selectedBook: SelectedBook? = nil
    @State private var readerBook: Book? = nil
    @State private var editingCategory: HomeCategory? = nil
    @State private var categoryToDelete: HomeCategory? = nil
    @State private var showReorderShelves = false
    @State private var reorderingBooksCategory: HomeCategory? = nil
    @State private var editingBook: Book? = nil
    @State private var bookToDelete: HomeBook? = nil
    @State private var bookToMarkFinished: Book? = nil

    // IDs currently in their dissolve-out phase — layout space is released
    // after the dissolve completes, creating a two-phase deletion.
    @State private var removingCategoryIDs: Set<UUID> = []

    @AppStorage("fathom.home.showRecentlyRead") private var showRecentlyRead = true

    // The observatory entry point into the Memory Garden.
    @State private var showMemoryGarden = false
    @State private var observatoryRefresh = 0

    @ObservedObject var search: LibrarySearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
                .padding(.horizontal, theme.layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, theme.layout.sectionSpacing)

            Divider()
                .padding(.horizontal, 20)

            ZStack {
                shelvesScroll
                    // Same focus idiom as the vocabulary overlay in RootView —
                    // the whole surface defocuses as one composite image.
                    .blur(radius: search.isActive ? 3 : 0)
                    .opacity(search.isActive ? 0 : 1)
                    .allowsHitTesting(!search.isActive)

                if search.isActive {
                    LibrarySearchResults(
                        books: search.results,
                        isEmptyResult: search.isEmptyResult,
                        query: search.query,
                        onTap: { id in selectedBook = SelectedBook(id: id) }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.42, bounce: 0.05), value: search.isActive)
        }
        .background(theme.colors.background)
        .task(id: viewModel.allBooks.count) {
            search.updateLibrary(viewModel.allBooks)
        }
    }

    // The sheet/cover chain hangs off this subview rather than off `body`.
    // Presentation is independent of rendering, so these still work while the
    // shelves are faded out behind the search results — a book tapped in the
    // results grid opens its details sheet exactly as one tapped on a shelf.
    private var shelvesScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: theme.layout.sectionSpacing) {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 60)
                } else {
                    if showRecentlyRead, let recentBook = viewModel.recentBook {
                        RecentlyReadTile(
                            book: recentBook,
                            progress: viewModel.recentBookProgress,
                            onTap: {
                                guard let book = viewModel.recentFullBook,
                                      downloadMonitor.isReadable(bookFilename: book.localFilename)
                                else { return }
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                readerBook = book
                            }
                        )
                        .padding(.horizontal, 20)
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    showRecentlyRead = false
                                }
                            } label: {
                                Label("Hide Recently Read", systemImage: "eye.slash")
                            }
                        }
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
                            onReorderBooks: category.books.count > 1
                                ? {
                                    let cat = category
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        reorderingBooksCategory = cat
                                    }
                                } : nil,
                            userCategories: userShelves,
                            onToggleCategoryMembership: { bookID, categoryID in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    viewModel.toggleBookInCategory(
                                        bookID: bookID, categoryID: categoryID)
                                }
                            },
                            onCreateShelf: { name, colorHex in
                                viewModel.createCategory(name: name, colorHex: colorHex)
                            },
                            onEditBook: { bookID in
                                Task { @MainActor in
                                    let allBooks = await bookRepository.listBooks()
                                    guard let book = allBooks.first(where: { $0.id == bookID })
                                    else { return }
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    editingBook = book
                                }
                            },
                            onDeleteBook: { bookID in
                                let hb = viewModel.categories.flatMap(\.books)
                                    .first(where: { $0.id == bookID })
                                guard let hb else { return }
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    bookToDelete = hb
                                }
                            },
                            onMarkFinished: { bookID in
                                Task {
                                    let books = await bookRepository.listBooks()
                                    guard let book = books.first(where: { $0.id == bookID }) else { return }
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    await MainActor.run { bookToMarkFinished = book }
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

                    if viewModel.categories.count > 1 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showReorderShelves = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Reorder Shelves")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(theme.colors.primary.opacity(0.8))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(
                                Group {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 32)
                        .padding(.bottom, 24)
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
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
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

            }
            .padding(.top, 36)
            .padding(.horizontal, 24)
            .presentationDetents([.height(216)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReorderShelves) {
            ReorderShelvesSheet(shelves: viewModel.categories) { newOrder in
                viewModel.applyShelfOrder(newOrder)
            }
        }
        .sheet(item: $reorderingBooksCategory) { category in
            let liveCategory =
                viewModel.categories.first(where: { $0.id == category.id }) ?? category
            ReorderBooksSheet(category: liveCategory) { newOrder in
                viewModel.applyBookOrder(in: liveCategory.id, newOrder: newOrder)
            }
        }
        .sheet(item: $editingBook) { book in
            let coverData: Data? = {
                guard let filename = book.coverFilename,
                    let url = BookFileStore.coverURL(for: filename)
                else { return nil }
                return try? Data(contentsOf: url)
            }()
            BookImportFlow(
                initial: BookCustomization(
                    id: book.id,
                    title: book.title,
                    author: book.author ?? "",
                    description: book.description ?? "",
                    coverImageData: coverData,
                    originalTitle: book.title,
                    originalAuthor: book.author,
                    originalLanguage: book.language,
                    epubURL: book.localURL
                ),
                isEditing: true,
                onConfirm: { edited in
                    Task { await viewModel.updateBook(id: book.id, customization: edited) }
                },
                onCancel: {}
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $bookToDelete) { book in
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Delete \"\(book.title)\"?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(
                        "This will permanently remove the book and all your highlights, notes, and bookmarks."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.horizontal)
                }
                .padding(.top, 10)

                HStack(spacing: 12) {
                    Button(role: .cancel) {
                        bookToDelete = nil
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
                        let id = book.id
                        bookToDelete = nil
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            viewModel.deleteBook(id: id)
                        }
                    } label: {
                        Text("Delete Book")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)
                            )
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.top, 36)
            .padding(.horizontal, 24)
            .presentationDetents([.height(236)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $readerBook) { book in
            if let url = book.localURL {
                ReaderScreen(
                    bookFileURL: url,
                    bookTitle: book.title,
                    bookID: book.id,
                    book: book,
                    bookRepository: bookRepository,
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
                // (The observatory refreshes itself via .fathomReadingSessionLogged,
                // which fires *after* the session write commits — no race.)
            }
        }
        .fullScreenCover(isPresented: $showMemoryGarden) {
            MemoryGardenView(bookRepository: bookRepository)
        }
        .onChange(of: showMemoryGarden) { _, isOpen in
            // Refresh when returning from the garden (a reveal may have happened).
            if !isOpen { observatoryRefresh &+= 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeScreenOpenReader)) { note in
            guard let bookID = note.userInfo?["bookID"] as? UUID else { return }
            Task {
                let books = await bookRepository.listBooks()
                guard let book = books.first(where: { $0.id == bookID }),
                      ICloudDownloadMonitor.shared.isReadable(bookFilename: book.localFilename)
                else { return }
                await MainActor.run { readerBook = book }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissReader)) { _ in
            readerBook = nil
        }
        .fullScreenCover(item: $bookToMarkFinished) { book in
            BookCompletionScreen(book: book, bookRepository: bookRepository)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookCompletionDidSave)) { _ in
            Task { await viewModel.load() }
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
        LibraryHeader(
            title: "Fathom",
            search: search,
            bookRepository: bookRepository,
            observatoryRefresh: observatoryRefresh,
            onOpenGarden: { showMemoryGarden = true }
        )
    }
}

// MARK: - Preview
#Preview {
    let repo = InMemoryBookRepository()
    let vm = HomeViewModel(
        bookRepository: repo,
        categoryRepository: InMemoryCategoryRepository()
    )
    HomeScreen(
        viewModel: vm,
        bookRepository: repo,
        search: LibrarySearchViewModel(bookRepository: repo)
    )
    .task { await vm.load() }
}
