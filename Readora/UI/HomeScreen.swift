import SwiftUI

struct HomeScreen: View {

    @ObservedObject var viewModel: HomeViewModel
    let bookRepository: BookRepository
    @Environment(\.appTheme) var theme

    @State private var readerBook: Book? = nil
    @Namespace private var namespace
    @State private var heroConfigs: [UUID: ScrollHeroEffectConfig] = [:]

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
                        BookCategorySection(
                            category: category,
                            config: binding(for: category.id),
                            namespace: namespace,
                            onBookTap: nil
                        )
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(theme.colors.background)
        .overlay {
            ZStack {
                ForEach(viewModel.categories) { category in
                    DetailHeroEffectScrollView(
                        config: binding(for: category.id),
                        namespace: namespace,
                        data: category.books,
                        id: \.id
                    ) { book, progress in
                        BookDetailHeroView(
                            config: binding(for: category.id),
                            book: book,
                            progress: progress,
                            namespace: namespace,
                            onReadTap: {
                                Task { @MainActor in
                                    let books = await bookRepository.listBooks()
                                    if let fullBook = books.first(where: { $0.id == book.id }) {
                                        readerBook = fullBook
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
        .fullScreenCover(item: $readerBook) { book in
            if let url = book.localURL {
                ReaderScreen(bookFileURL: url, bookTitle: book.title, bookID: book.id)
                    .id(book.id)
            }
        }
    }

    private func binding(for id: UUID) -> Binding<ScrollHeroEffectConfig> {
        Binding(
            get: { heroConfigs[id] ?? .init() },
            set: { heroConfigs[id] = $0 }
        )
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
