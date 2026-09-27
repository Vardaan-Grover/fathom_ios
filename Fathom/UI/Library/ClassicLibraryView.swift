import SwiftUI
import UniformTypeIdentifiers

private struct SelectedBook: Identifiable {
  let id: UUID
}

struct ClassicLibraryView: View {
  @ObservedObject var viewModel: HomeViewModel
  let bookRepository: BookRepository
  /// Opens the file importer, which lives up in RootView alongside the tab bar.
  let onAddBook: () -> Void
  @Environment(\.appTheme) var theme

  @AppStorage("fathom.home.classic.showMetadata") private var showGridMetadata = false

  @State private var selectedBook: SelectedBook? = nil
  @State private var readerBook: Book? = nil
  @State private var editingBook: Book? = nil
  @State private var bookToDelete: HomeBook? = nil
  @State private var bookToMarkFinished: Book? = nil
  @State private var showReorderShelves = false
  @State private var reorderingBooksCategory: HomeCategory? = nil

  @ObservedObject private var downloadMonitor = ICloudDownloadMonitor.shared
  @AppStorage("fathom.home.showRecentlyRead") private var showRecentlyRead = true

  @State private var showMemoryGarden = false
  @State private var observatoryRefresh = 0
  @ObservedObject var search: LibrarySearchViewModel

  var body: some View {
    NavigationStack {
      Group {
        if isLibraryEmpty {
          // Nothing to scroll, so the header just sits at the top.
          VStack(spacing: 0) {
            headerBlock
            EmptyLibraryView(onAddBook: onAddBook)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              // Clears the floating tab bar below.
              .padding(.bottom, 90)
          }
          .background(theme.colors.background.ignoresSafeArea())
        } else {
          mainContent
        }
      }
      // Only the blur is pinned; the header rides the scroll content.
      .topScrollEdgeBlur(height: 62)
      .animation(.spring(duration: 0.42, bounce: 0.05), value: search.isActive)
      // Cross-fade the empty state out when the first book lands.
      .animation(.easeInOut(duration: 0.4), value: isLibraryEmpty)
      .task(id: viewModel.allBooks.count) {
        search.updateLibrary(viewModel.allBooks)
      }
      .fullScreenCover(isPresented: $showMemoryGarden) {
        MemoryGardenView(bookRepository: bookRepository)
      }
      .onChange(of: showMemoryGarden) { _, isOpen in
        if !isOpen { observatoryRefresh &+= 1 }
      }
    }
  }
  
  /// See the matching property on HomeScreen — a first-run library is no books
  /// and no shelves the user made themselves.
  private var isLibraryEmpty: Bool {
    viewModel.hasLoaded
      && viewModel.allBooks.isEmpty
      && !viewModel.categories.contains(where: { !$0.shelfColorHex.isEmpty })
  }

  // MARK: mainContent
  //
  // The header, the grid, and the search results share this one scroll view —
  // see the matching note on HomeScreen.shelvesScroll for why the results are
  // composed in rather than presented over the top.
  private var mainContent: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 24) {
        headerBlock

        if search.isActive {
          searchResults
            .transition(.opacity)
        } else {
          // Scoped rather than applied to the whole VStack: the header and the
          // results grid each supply their own horizontal padding, so a blanket
          // one here would double it on both.
          VStack(spacing: 24) {
            collectionsRow
            if showRecentlyRead, let recentBook = viewModel.recentBook {
              RecentlyReadTile(
                book: recentBook,
                progress: viewModel.recentBookProgress,
                onTap: {
                  guard let book = viewModel.recentFullBook else { return }
                  // Same as the home screen's tile: a guard here made the tap
                  // do nothing while the file was still arriving. Ask for it
                  // and open; the loader waits for the download.
                  if !downloadMonitor.isReadable(bookFilename: book.localFilename),
                    let filename = book.localFilename
                  {
                    downloadMonitor.requestDownload(filename: filename)
                  }
                  UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                  readerBook = book
                }
              )
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
            libraryGrid
          }
          .padding(.horizontal, theme.layout.horizontalPadding)
        }
      }
      .padding(.top, 16)
      .padding(.bottom, 90)  // Room for tab bar
    }
    .background(theme.colors.background.ignoresSafeArea())
    // The keyboard follows the drag, but the search surface stays up —
    // losing focus is not intent to close, only Cancel is.
    .scrollDismissesKeyboard(.interactively)
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
        Task { await viewModel.load() }
      }
    }
    .fullScreenCover(item: $bookToMarkFinished) { book in
      BookCompletionScreen(book: book, bookRepository: bookRepository)
    }
    .onReceive(NotificationCenter.default.publisher(for: .fathomSyncDidApplyRemoteChanges)) { _ in
      Task { await viewModel.load() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookCompletionDidSave)) { _ in
      Task { await viewModel.load() }
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
      deleteConfirmationSheet(for: book)
    }
    .sheet(item: $reorderingBooksCategory) { category in
      let liveCategory = viewModel.categories.first(where: { $0.id == category.id }) ?? category
      ReorderBooksSheet(category: liveCategory) { newOrder in
        viewModel.applyBookOrder(in: liveCategory.id, newOrder: newOrder)
      }
    }
  }

    // MARK: collectionsRow
  private var collectionsRow: some View {
    NavigationLink {
      CollectionsListView(viewModel: viewModel, bookRepository: bookRepository)
    } label: {
      HStack(spacing: 16) {
        Image(systemName: "list.bullet.rectangle.portrait.fill")
          .font(.system(size: 24))
          .foregroundStyle(theme.colors.primary)

        Text("Collections")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(theme.colors.primary)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(theme.colors.secondary.opacity(0.5))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .background(
        Color(.secondarySystemFill),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
    .buttonStyle(.plain)
  }

  // MARK: libraryGrid
  private var libraryGrid: some View {
    let columns = [
      GridItem(.flexible(), spacing: 16),
      GridItem(.flexible(), spacing: 16),
    ]

    let myLibrary = viewModel.categories.first { $0.id == HomeViewModel.myLibraryID }
    let books = myLibrary?.books ?? []

    return LazyVGrid(columns: columns, spacing: 28) {
      ForEach(books) { book in
        bookCell(for: book)
          .id(book.id)
      }
    }
  }

  // MARK: bookCell
  @ViewBuilder
  private func bookCell(for book: HomeBook) -> some View {
    let userShelves = viewModel.categories.filter { !$0.shelfColorHex.isEmpty }

    GeometryReader { geo in
      let w = geo.size.width
      let h = w * 1.5  // Standard 2:3 aspect ratio

      VStack(alignment: .leading, spacing: 8) {
        ZStack(alignment: .topTrailing) {
          BookCoverView(
            book: book,
            width: w,
            height: h,
            userCategories: userShelves,
            onToggleCategory: { categoryID in
              withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                viewModel.toggleBookInCategory(bookID: book.id, categoryID: categoryID)
              }
            },
            onCreateShelf: { name, colorHex in
              viewModel.createCategory(name: name, colorHex: colorHex)
            },
            onEdit: {
              Task { @MainActor in
                let allBooks = await bookRepository.listBooks()
                guard let fullBook = allBooks.first(where: { $0.id == book.id }) else { return }
                editingBook = fullBook
              }
            },
            onDelete: {
              bookToDelete = book
            },
            onMarkFinished: {
              Task {
                let books = await bookRepository.listBooks()
                guard let fullBook = books.first(where: { $0.id == book.id }) else { return }
                await MainActor.run { bookToMarkFinished = fullBook }
              }
            }
          )
          .onTapGesture {
            selectedBook = SelectedBook(id: book.id)
          }
        }

        if showGridMetadata {
          VStack(alignment: .leading, spacing: 2) {
            Text(book.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(theme.colors.primary)
              .lineLimit(2)

            Text(book.author)
              .font(.system(size: 12, weight: .regular))
              .foregroundColor(theme.colors.secondary)
              .lineLimit(1)
          }
          .padding(.horizontal, 4)
        }
      }
    }
    .aspectRatio(showGridMetadata ? 0.55 : 0.66, contentMode: .fit)
  }
  
  // MARK: deleteConfirmationSheet
  private func deleteConfirmationSheet(for book: HomeBook) -> some View {
    VStack(spacing: 24) {
      VStack(spacing: 8) {
        Text("Delete \"\(book.title)\"?")
          .font(.title2.bold())
          .multilineTextAlignment(.center)

        Text("This will permanently remove the book and all your highlights, notes, and bookmarks.")
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

  // MARK: - Header

  /// The header and its padding, as one unit. Lives inside the scroll content
  /// so it scrolls away with the grid — there is no fade, it simply leaves.
  private var headerBlock: some View {
    LibraryHeader(
      title: "Library",
      search: search,
      bookRepository: bookRepository,
      observatoryRefresh: observatoryRefresh,
      onOpenGarden: { showMemoryGarden = true },
      menu: { sortMenu }
    )
    .padding(.horizontal, theme.layout.horizontalPadding)
  }

  // Sort is a rare action, so it lives in a menu rather than holding a
  // permanent slot beside the observatory and search capsules.
  private var sortMenu: some View {
    Menu {
      Button {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let cat = viewModel.categories.first(where: { $0.id == HomeViewModel.myLibraryID }) {
          reorderingBooksCategory = cat
        }
      } label: {
        Label("Reorder Books", systemImage: "arrow.up.arrow.down")
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(theme.colors.primary)
        .frame(width: 46, height: 46)
        .contentShape(.circle)
        .glassCapsule(interactive: true)
    }
    .accessibilityLabel("Library options")
  }

  // MARK: - Search results

  private var searchResults: some View {
    LibrarySearchResults(
      books: search.results,
      isEmptyResult: search.isEmptyResult,
      query: search.query,
      onTap: { id in selectedBook = SelectedBook(id: id) },
      userCategories: viewModel.categories.filter { !$0.shelfColorHex.isEmpty },
      onToggleCategory: { bookID, categoryID in
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
          viewModel.toggleBookInCategory(bookID: bookID, categoryID: categoryID)
        }
      },
      onCreateShelf: { name, colorHex in
        viewModel.createCategory(name: name, colorHex: colorHex)
      },
      onEditBook: { bookID in
        Task { @MainActor in
          let allBooks = await bookRepository.listBooks()
          guard let fullBook = allBooks.first(where: { $0.id == bookID }) else { return }
          try? await Task.sleep(nanoseconds: 500_000_000)
          editingBook = fullBook
        }
      },
      onDeleteBook: { bookID in
        guard let hb = search.results.first(where: { $0.id == bookID }) else { return }
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 500_000_000)
          bookToDelete = hb
        }
      },
      onMarkFinished: { bookID in
        Task {
          let books = await bookRepository.listBooks()
          guard let fullBook = books.first(where: { $0.id == bookID }) else { return }
          try? await Task.sleep(nanoseconds: 500_000_000)
          await MainActor.run { bookToMarkFinished = fullBook }
        }
      },
      // The caller owns the scroll view here, so the grid contributes its
      // content directly rather than nesting a second one.
      isScrollable: false
    )
  }
}
