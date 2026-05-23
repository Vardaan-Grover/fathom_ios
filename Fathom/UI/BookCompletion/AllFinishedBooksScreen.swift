import SwiftUI

// MARK: - AllFinishedBooksScreen
//
// Profile → "Books I've Read": all books where finishedAt is set,
// sorted most-recently-finished first. Each row shows cover, title,
// rating dots, and a truncated first line of the reflection.

struct AllFinishedBooksScreen: View {
    let bookRepository: BookRepository

    @Environment(\.appTheme) private var theme

    @State private var books: [Book] = []
    @State private var selectedBook: Book? = nil

    private var accent: Color { theme.colors.shelfAccent }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if books.isEmpty {
                emptyState
            } else {
                bookList
            }
        }
        .navigationTitle("Books I've Read")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .bookCompletionDidSave)) { _ in
            Task { await load() }
        }
        .fullScreenCover(item: $selectedBook) { book in
            BookCompletionScreen(book: book, bookRepository: bookRepository)
        }
    }

    // MARK: - List

    private var bookList: some View {
        List {
            ForEach(books) { book in
                BookFinishedRow(book: book, accent: accent, theme: theme)
                    .listRowBackground(theme.colors.surface)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedBook = book }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 90, for: .scrollContent)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        CrossBookEmptyState(
            symbol: "books.vertical",
            title: "No finished books yet",
            subtitle: "When you finish a book and close the chapter, it'll appear here.",
            accent: accent
        )
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        let all = await bookRepository.listBooks()
        books = all
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }
}

// MARK: - BookFinishedRow

private struct BookFinishedRow: View {
    let book: Book
    let accent: Color
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 14) {
            MiniBookCover(book: book, width: 44, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(theme.typography.headline)
                    .foregroundColor(theme.colors.primary)
                    .lineLimit(1)

                if let author = book.author {
                    Text(author)
                        .font(theme.typography.subheadline)
                        .foregroundColor(theme.colors.secondary)
                        .lineLimit(1)
                }

                ratingDots

                if let reflection = book.reflection, !reflection.isEmpty {
                    Text(reflection)
                        .font(theme.typography.caption)
                        .foregroundColor(theme.colors.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.colors.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var ratingDots: some View {
        if let rating = book.rating {
            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { i in
                    Circle()
                        .fill(i <= rating ? accent : accent.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }
}
