import SwiftUI

struct BookCoverView: View {
    let book: HomeBook

    @State private var shouldShowMenu = true

    init(book: HomeBook) {
        self.book = book
    }

    private let coverWidth: CGFloat = 120
    private let coverHeight: CGFloat = 168

    var body: some View {
        ZStack(alignment: .topLeading) {
            coverBackground
            spineShading
            textOverlay
        }
        .frame(width: coverWidth, height: coverHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 4)
        .contextMenu(shouldShowMenu ? menuItems : nil)
    }

    @ViewBuilder
    private var coverBackground: some View {
        if let filename = book.coverFilename,
            let url = BookFileStore.coverURL(for: filename),
            let uiImage = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: coverWidth, height: coverHeight)
                .clipped()
        } else {
            book.coverColor
                .frame(width: coverWidth, height: coverHeight)
        }
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

    private var menuItems = ContextMenu {
        ControlGroup {
            Button {
            } label: {
                Label("Favorite", systemImage: "heart")
            }
            Button {
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
