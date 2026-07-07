import SwiftUI

struct BookCoverView: View {
    let book: HomeBook
    let width: CGFloat
    let height: CGFloat
    var userCategories: [HomeCategory] = []
    var onToggleCategory: ((UUID) -> Void)? = nil
    var onCreateShelf: ((String, String) -> HomeCategory?)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onMarkFinished: (() -> Void)? = nil

    @State private var showShelfPicker = false
    @State private var coverImage: UIImage? = nil

    init(
        book: HomeBook,
        width: CGFloat = 120,
        height: CGFloat = 168,
        userCategories: [HomeCategory] = [],
        onToggleCategory: ((UUID) -> Void)? = nil,
        onCreateShelf: ((String, String) -> HomeCategory?)? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onMarkFinished: (() -> Void)? = nil
    ) {
        self.book = book
        self.width = width
        self.height = height
        self.userCategories = userCategories
        self.onToggleCategory = onToggleCategory
        self.onCreateShelf = onCreateShelf
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onMarkFinished = onMarkFinished
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            coverBackground
            spineShading
            textOverlay
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 4)
        .contextMenu { contextMenuContent }
        .task(id: book.coverFilename) {
            coverImage = Self.loadCoverImage(filename: book.coverFilename)
        }
        .sheet(isPresented: $showShelfPicker) {
            ShelfPickerSheet(
                categories: userCategories,
                initialSelectedIDs: book.categoryIDs,
                onCreateShelf: { name, colorHex in onCreateShelf?(name, colorHex) }
            ) { added, removed in
                for id in added { onToggleCategory?(id) }
                for id in removed { onToggleCategory?(id) }
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            onMarkFinished?()
        } label: {
            Label("Mark as Finished", systemImage: "checkmark.seal")
        }
        Button {
            onEdit?()
        } label: {
            Label("Edit Book", systemImage: "pencil")
        }
        Button {
            showShelfPicker = true
        } label: {
            Label("Manage Shelves", systemImage: "books.vertical")
        }
        Button(role: .destructive) {
            onDelete?()
        } label: {
            Label("Delete Book", systemImage: "trash")
        }
    }

    // MARK: - Visual layers

    @ViewBuilder
    private var coverBackground: some View {
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else {
            book.coverColor
                .frame(width: width, height: height)
        }
    }

    private static func loadCoverImage(filename: String?) -> UIImage? {
        BookFileStore.coverImage(for: filename)
    }

    // Subtle left-edge spine shading — only visible on the color fallback,
    // but harmless over a real cover image.
    private var spineShading: some View {
        LinearGradient(
            colors: [.black.opacity(0.28), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 12)
    }

    // Title + author text is only shown when no real cover image is available.
    @ViewBuilder
    private var textOverlay: some View {
        if book.coverFilename == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(book.textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(5)

                Spacer()

                Text(book.author)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(book.textColor?.opacity(0.70))
                    .lineLimit(2)
            }
            .padding(10)
        }
    }
}

#Preview {
    HStack(spacing: 10) {
        BookCoverView(
            book: HomeBook(
                id: UUID(),
                title: "The Design of Everyday Things",
                author: "Don Norman",
                coverColor: Color(hex: "F5C518"),
                textColor: .black,
                coverFilename: nil
            ))
        BookCoverView(
            book: HomeBook(
                id: UUID(),
                title: "Read People Like a Book",
                author: "Patrick King",
                coverColor: Color(hex: "1A3A6B"),
                textColor: Color(hex: "F5C518"),
                coverFilename: nil
            ))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
