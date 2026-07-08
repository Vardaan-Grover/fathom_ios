import SwiftUI

struct BookmarksListView: View {
    let bookID: UUID
    var onSelect: (String) -> Void

    @State private var bookmarks: [Bookmark] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if bookmarks.isEmpty {
                emptyState
            } else {
                bookmarksList
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { loadBookmarks() }
        .onReceive(
            NotificationCenter.default.publisher(for: BookmarkStore.didChangeNotification)
        ) { notification in
            guard let changedID = notification.object as? UUID, changedID == bookID else { return }
            loadBookmarks()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bookmarks")
                    .font(.system(size: 17, weight: .semibold))
                Text(countLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bookmarks.count)
            }
            Spacer()
            Button { dismiss() } label: {
                ZStack {
                    Circle()
                        .fill(Color(.systemFill))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var countLabel: String {
        let n = bookmarks.count
        return "\(n) \(n == 1 ? "bookmark" : "bookmarks")"
    }

    // MARK: - List

    private var bookmarksList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(bookmarks) { bookmark in
                    BookmarkCard(bookmark: bookmark)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(bookmark.locatorJSON)
                            dismiss()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                BookmarkStore.shared.delete(id: bookmark.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                Text("No Bookmarks Yet")
                    .font(.system(size: 17, weight: .semibold))
                Text("Tap the bookmark icon in the\nreader menu to save your place.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Data

    private func loadBookmarks() {
        bookmarks = BookmarkStore.shared.bookmarks(forBookID: bookID)
    }
}

// MARK: - Bookmark Card

private struct BookmarkCard: View {
    let bookmark: Bookmark

    var body: some View {
        HStack(spacing: 0) {
            // Crimson left rail
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(red: 0.78, green: 0.08, blue: 0.15))
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    if let chapter = bookmark.chapterTitle, !chapter.isEmpty {
                        Text(chapter.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let page = bookmark.pageNumber {
                        let hasPrecedingChapter = bookmark.chapterTitle?.isEmpty == false
                        Text((hasPrecedingChapter ? " · " : "") + "p. \(page)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(bookmark.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 14)
                .padding(.bottom, 10)
                .padding(.trailing, 14)

                Text("\(Int(bookmark.progression * 100))% through book")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
            }
            .padding(.leading, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.78, green: 0.08, blue: 0.15).opacity(0.05))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
