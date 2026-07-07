import SwiftUI
import UniformTypeIdentifiers

private struct SelectedBook: Identifiable {
  let id: UUID
}

@Observable private final class TopBarScrollState {
  var offset: CGFloat = 0
}

struct ClassicLibraryView: View {
  @ObservedObject var viewModel: HomeViewModel
  let bookRepository: BookRepository
  @Environment(\.appTheme) var theme

  @AppStorage("fathom.home.classic.showMetadata") private var showGridMetadata = false

  @State private var selectedBook: SelectedBook? = nil
  @State private var readerBook: Book? = nil
  @State private var editingBook: Book? = nil
  @State private var bookToDelete: HomeBook? = nil
  @State private var bookToMarkFinished: Book? = nil
  @State private var showReorderShelves = false
  @State private var reorderingBooksCategory: HomeCategory? = nil
  @State private var topBarScrollState = TopBarScrollState()

  @ObservedObject private var downloadMonitor = ICloudDownloadMonitor.shared
  @AppStorage("fathom.home.showRecentlyRead") private var showRecentlyRead = true

  var body: some View {
    NavigationStack {
      ZStack {
        mainContent
        TopBarOverlay(
          scrollState: topBarScrollState,
          viewModel: viewModel,
          reorderingBooksCategory: $reorderingBooksCategory
        )
      }
      
    }
  }
  
  // MARK: mainContent
  private var mainContent: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 24) {
        Color.clear.frame(height: 56)
        collectionsRow
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
      .padding(.top, 16)
      .padding(.bottom, 90)  // Room for tab bar
    }
    .background(theme.colors.background.ignoresSafeArea())
    .onScrollGeometryChange(for: CGFloat.self) { geo in
      geo.contentOffset.y
    } action: { _, newValue in
      topBarScrollState.offset = max(0, newValue)
    }
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
}

// MARK: - TopBarOverlay

private struct TopBarOverlay: View {
  let scrollState: TopBarScrollState
  let viewModel: HomeViewModel
  @Binding var reorderingBooksCategory: HomeCategory?
  @Environment(\.appTheme) var theme

  private var opacity: Double {
    let fadeStart: CGFloat = 16
    let fadeEnd: CGFloat = 64
    return Double(max(0, min(1, 1 - (scrollState.offset - fadeStart) / (fadeEnd - fadeStart))))
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Library")
          .font(.system(size: 34, weight: .bold, design: .serif))
          .foregroundColor(theme.colors.primary)
        Spacer()
        Button {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          if let cat = viewModel.categories.first(where: { $0.id == HomeViewModel.myLibraryID }) {
            reorderingBooksCategory = cat
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.colors.primary.opacity(0.8))
            .frame(width: 32, height: 32)
        }
      }
      .padding(.horizontal, theme.layout.horizontalPadding)
      .padding(.top, 16)
      .background {
        theme.colors.background
          .opacity(0.9)
          .padding(.top, -28)
          .blur(radius: 12, opaque: false)
          .ignoresSafeArea(edges: .top)
      }
      .opacity(opacity)
      Spacer()
    }
  }
}
