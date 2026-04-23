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
                        BookCategorySection(category: category, onBookTap: { id in
                            selectedBook = SelectedBook(id: id)
                        })
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
        }
        .fullScreenCover(item: $readerBook) { book in
            if let url = book.localURL {
                ReaderScreen(bookFileURL: url, bookTitle: book.title, bookID: book.id)
            }
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
