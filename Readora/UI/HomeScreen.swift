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
                        BookCategorySection(
                            category: category,
                            onBookTap: { id in selectedBook = SelectedBook(id: id) },
                            onEdit: isUserShelf ? { editingCategory = category } : nil,
                            onDelete: isUserShelf ? { categoryToDelete = category } : nil
                        )
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
                Task { await viewModel.updateCategory(id: category.id, name: name, colorHex: colorHex) }
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
                if let id = categoryToDelete?.id {
                    Task { await viewModel.deleteCategory(id: id) }
                }
                categoryToDelete = nil
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
