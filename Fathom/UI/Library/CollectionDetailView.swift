import SwiftUI

struct CollectionDetailView: View {
    let category: HomeCategory
    @ObservedObject var viewModel: HomeViewModel
    let bookRepository: BookRepository
    @Environment(\.appTheme) var theme

    @AppStorage("fathom.home.classic.showMetadata") private var showGridMetadata = false

    @State private var selectedBook: UUID? = nil
    @State private var readerBook: Book? = nil
    @State private var reorderingBooksCategory: HomeCategory? = nil

    var body: some View {
        let liveCategory = viewModel.categories.first(where: { $0.id == category.id }) ?? category

        ScrollView {
            let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(liveCategory.books) { book in
                    bookCell(for: book)
                }
            }
            .padding(.horizontal, theme.layout.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 90)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(liveCategory.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    reorderingBooksCategory = liveCategory
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primary.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
            }
        }
        .sheet(item: $reorderingBooksCategory) { category in
            let liveCategory = viewModel.categories.first(where: { $0.id == category.id }) ?? category
            ReorderBooksSheet(category: liveCategory) { newOrder in
                viewModel.applyBookOrder(in: liveCategory.id, newOrder: newOrder)
            }
        }
        .sheet(
            item: Binding(
                get: { selectedBook.map { SelectedBookWrapper(id: $0) } },
                set: { selectedBook = $0?.id }
            )
        ) { selection in
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
                            selectedBook = book.id
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func bookCell(for book: HomeBook) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 1.5

            VStack(alignment: .leading, spacing: 8) {
                BookCoverView(
                    book: book,
                    width: w,
                    height: h,
                    userCategories: viewModel.categories.filter { !$0.shelfColorHex.isEmpty },
                    onToggleCategory: { categoryID in
                        withAnimation {
                            viewModel.toggleBookInCategory(bookID: book.id, categoryID: categoryID)
                        }
                    },
                    onCreateShelf: { name, colorHex in
                        viewModel.createCategory(name: name, colorHex: colorHex)
                    }
                )
                .onTapGesture {
                    selectedBook = book.id
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
}

private struct SelectedBookWrapper: Identifiable {
    let id: UUID
}
