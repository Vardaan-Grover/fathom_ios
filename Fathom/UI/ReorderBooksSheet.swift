import SwiftUI

struct ReorderBooksSheet: View {
    let category: HomeCategory
    // onCommit is called on every drag move — no explicit save needed
    let onCommit: ([HomeBook]) -> Void

    @State private var books: [HomeBook]
    @Environment(\.dismiss) private var dismiss

    init(category: HomeCategory, onCommit: @escaping ([HomeBook]) -> Void) {
        self.category = category
        self.onCommit = onCommit
        _books = State(initialValue: category.books)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bookList
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - Compact inline header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Arrange Books")
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 5) {
                    Capsule()
                        .fill(category.shelfColor)
                        .frame(width: 6, height: 6)
                    Text(category.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Done") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - List

    private var bookList: some View {
        List {
            ForEach(books) { book in
                BookReorderRow(book: book)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
            .onMove { from, to in
                UISelectionFeedbackGenerator().selectionChanged()
                books.move(fromOffsets: from, toOffset: to)
                onCommit(books)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Row

private struct BookReorderRow: View {
    let book: HomeBook

    var body: some View {
        HStack(spacing: 12) {
            bookCover
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(book.author)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var bookCover: some View {
        if let filename = book.coverFilename,
           let url = BookFileStore.coverURL(for: filename),
           let uiImage = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack(alignment: .topLeading) {
                (book.coverColor ?? Color(.secondarySystemFill))
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.25), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 7),
                        alignment: .leading
                    )
                Text(book.title)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(book.textColor)
                    .lineLimit(4)
                    .padding(4)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let books = [
        HomeBook(id: UUID(), title: "Crime and Punishment",
                 author: "Fyodor Dostoevsky", coverColor: Color(hex: "1A5EA8"),
                 textColor: .white, coverFilename: nil),
        HomeBook(id: UUID(), title: "No Longer Human",
                 author: "Osamu Dazai", coverColor: Color(hex: "C0507A"),
                 textColor: .white, coverFilename: nil),
        HomeBook(id: UUID(), title: "Metamorphosis",
                 author: "Franz Kafka", coverColor: Color(hex: "2A6B3E"),
                 textColor: .white, coverFilename: nil),
    ]
    let category = HomeCategory(
        id: HomeViewModel.myLibraryID, name: "My Library", books: books,
        shelfColor: Color(hex: "4A7DB5"), shelfColorHex: ""
    )
    ReorderBooksSheet(category: category) { _ in }
}
