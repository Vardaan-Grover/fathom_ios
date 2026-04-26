import SwiftUI

struct BookCategorySection: View {
    let category: HomeCategory
    var onBookTap: ((UUID) -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private let sectionHeight: CGFloat = 196
    private let shelfBandHeight: CGFloat = 72
    private let bookTopPadding: CGFloat = 12
    private let bookBottomPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader
                .padding(.horizontal, 20)

            bookShelfArea
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text(category.name)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 12) {
                Text("\(category.books.count) books")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                if onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("Edit Shelf", systemImage: "pencil")
                            }
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete Shelf", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    private var bookShelfArea: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(category.books) { book in
                        BookCoverView(book: book)
                            .onTapGesture { onBookTap?(book.id) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, bookTopPadding)
                .padding(.bottom, bookBottomPadding)
            }

            shelfBand
        }
        .frame(height: sectionHeight)
    }

    private var shelfBand: some View {
        ZStack {
            // Glass body: thin material blurred background + a tint from the category color
            Rectangle()
                .fill(category.shelfColor.opacity(0.40))
                .overlay(
                    VStack {
                        LinearGradient(
                            colors: [.white.opacity(0.50), .white.opacity(0.20)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1.5)

                        Spacer()

                        LinearGradient(
                            colors: [.white.opacity(0.40), .white.opacity(0.10)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1.0)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(height: shelfBandHeight)

            // Silver bookend knobs on both ends
            HStack {
                silverKnob.padding(.leading, 8)
                Spacer()
                silverKnob.padding(.trailing, 8)
            }
            .frame(height: shelfBandHeight)
        }
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }

    private var silverKnob: some View {
        Image("BrushedMetalKnob")
            .resizable()
            .scaledToFill()
            .frame(width: 20, height: 20)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(white: 0.40), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.40), radius: 3, x: 1, y: 2)
    }
}


#Preview {
    let books = [
        HomeBook(id: UUID(), title: "Bauhaus", author: "Frank Whitford", coverColor: Color(hex: "1A5EA8"), textColor: .white, coverFilename: nil),
        HomeBook(id: UUID(), title: "Dieter Rams", author: "Klaus Klemp", coverColor: Color(hex: "E84B1F"), textColor: .white, coverFilename: nil),
        HomeBook(id: UUID(), title: "The Design of Everyday Things", author: "Don Norman", coverColor: Color(hex: "F5C518"), textColor: .black, coverFilename: nil),
    ]
    let category = HomeCategory(id: UUID(), name: "Design", books: books, shelfColor: Color(hex: "4A7DB5"), shelfColorHex: "4A7DB5")

    ScrollView {
        BookCategorySection(category: category, onEdit: {}, onDelete: {})
    }
    .background(Color(.systemGroupedBackground))
}
