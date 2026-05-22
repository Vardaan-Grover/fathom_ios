import SwiftUI

// MARK: - AllBookmarksScreen
//
// Cross-book view of every bookmark. Searchable + filterable by book.
// No color filter (bookmarks have no color).

struct AllBookmarksScreen: View {
    @StateObject private var directory = BookDirectory()

    @State private var bookmarks: [Bookmark] = []
    @State private var search: String = ""
    @State private var bookFilter: Set<UUID> = []
    @State private var showBookFilter = false

    private var perBookCounts: [UUID: Int] {
        Dictionary(bookmarks.map { ($0.bookID, 1) }, uniquingKeysWith: +)
    }

    private var filtered: [Bookmark] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return bookmarks.filter { bm in
            if !bookFilter.isEmpty && !bookFilter.contains(bm.bookID) { return false }
            if !q.isEmpty {
                let bookTitle = directory.byID[bm.bookID]?.title.lowercased() ?? ""
                let chapter = (bm.chapterTitle ?? "").lowercased()
                if !(bookTitle.contains(q) || chapter.contains(q)) { return false }
            }
            return true
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if !bookmarks.isEmpty {
                    filterBar
                }

                if filtered.isEmpty {
                    if bookmarks.isEmpty {
                        CrossBookEmptyState(
                            symbol: "bookmark",
                            title: "No Bookmarks Yet",
                            subtitle: "Tap the bookmark icon in the reader menu to save your place.",
                            accent: Color(red: 0.78, green: 0.08, blue: 0.15)
                        )
                    } else {
                        CrossBookEmptyState(
                            symbol: "magnifyingglass",
                            title: "No Matches",
                            subtitle: "Try a different search or filter."
                        )
                    }
                } else {
                    bookmarksList
                }
            }
        }
        .navigationTitle("All Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("All Bookmarks").font(.system(size: 16, weight: .semibold))
                    Text("\(filtered.count) of \(bookmarks.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: filtered.count)
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search bookmarks")
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: bookFilter)
        .sheet(isPresented: $showBookFilter) {
            SettingsBookFilterSheet(
                books: directory.allBooks.filter { perBookCounts[$0.id] != nil },
                counts: perBookCounts,
                selection: $bookFilter
            )
        }
        .onAppear {
            directory.reload()
            loadBookmarks()
        }
        .onReceive(NotificationCenter.default.publisher(for: BookmarkStore.didChangeNotification)) { _ in
            loadBookmarks()
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: bookFilter.isEmpty
                        ? "All Books"
                        : "\(bookFilter.count) \(bookFilter.count == 1 ? "Book" : "Books")",
                    symbol: "books.vertical",
                    isSelected: !bookFilter.isEmpty
                ) {
                    showBookFilter = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var bookmarksList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { bookmark in
                    BookmarkCrossBookCard(
                        bookmark: bookmark,
                        book: directory.byID[bookmark.bookID]
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        ProfileBookOpener.open(bookID: bookmark.bookID, locatorJSON: bookmark.locatorJSON)
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
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
    }

    private func loadBookmarks() {
        bookmarks = BookmarkStore.shared.allBookmarks()
        bookFilter = bookFilter.filter { id in bookmarks.contains(where: { $0.bookID == id }) }
    }
}

// MARK: - BookmarkCrossBookCard

private struct BookmarkCrossBookCard: View {
    let bookmark: Bookmark
    let book: Book?
    let onTap: () -> Void

    private let railColor = Color(red: 0.78, green: 0.08, blue: 0.15)

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(railColor)
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        MiniBookCover(book: book, width: 22, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(book?.title ?? "Unknown Book")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 0) {
                                if let chapter = bookmark.chapterTitle, !chapter.isEmpty {
                                    Text(chapter).lineLimit(1)
                                }
                                if let page = bookmark.pageNumber {
                                    let hasChapter = bookmark.chapterTitle?.isEmpty == false
                                    Text((hasChapter ? " · " : "") + "p. \(page)")
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(bookmark.createdAt, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 12)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(railColor.opacity(0.05))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(railColor.opacity(0.2), lineWidth: 1)
                )
            )
        }
        .buttonStyle(.plain)
    }
}
