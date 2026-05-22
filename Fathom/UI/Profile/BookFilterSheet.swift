import SwiftUI

// MARK: - BookFilterSheet
//
// Multi-select sheet for filtering the All Notes / Highlights / Bookmarks
// screens by book. Only lists books that actually have items on the
// caller's screen.

struct SettingsBookFilterSheet: View {
    /// All books available for filtering.
    let books: [Book]
    /// Number of items each book contributes — shown as a count in each row.
    let counts: [UUID: Int]

    @Binding var selection: Set<UUID>

    @Environment(\.dismiss) private var dismiss

    @State private var search: String = ""

    private var filtered: [Book] {
        let trimmed = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return books }
        return books.filter {
            $0.title.lowercased().contains(trimmed)
            || ($0.author?.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { book in
                    Button {
                        toggle(book.id)
                    } label: {
                        bookRow(book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search books")
            .navigationTitle("Filter by Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !selection.isEmpty {
                        Button("Clear") { selection.removeAll() }
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ id: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            MiniBookCover(book: book, width: 36, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let count = counts[book.id], count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color(.tertiarySystemFill))
                    )
            }

            Image(systemName: selection.contains(book.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(
                    selection.contains(book.id) ? Color.accentColor : Color(.tertiaryLabel)
                )
        }
        .contentShape(Rectangle())
    }
}
