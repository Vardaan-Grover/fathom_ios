import SwiftUI

// MARK: - AllNotesScreen
//
// Cross-book view of every note. Searchable + filterable by book and by
// highlight color. Tapping a card opens that book in the reader at the
// note's locator.

struct AllNotesScreen: View {
    @StateObject private var directory = BookDirectory()

    @State private var notes: [Note] = []
    @State private var search: String = ""
    @State private var selectedColor: HighlightColor? = nil
    @State private var bookFilter: Set<UUID> = []
    @State private var showBookFilter = false

    // MARK: - Derived

    private var presentColors: [HighlightColor] {
        HighlightColor.allCases.filter { c in notes.contains { $0.highlightColor == c } }
    }

    private var perBookCounts: [UUID: Int] {
        Dictionary(notes.map { ($0.bookID, 1) }, uniquingKeysWith: +)
    }

    private var filtered: [Note] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return notes.filter { note in
            if let selectedColor, note.highlightColor != selectedColor { return false }
            if !bookFilter.isEmpty && !bookFilter.contains(note.bookID) { return false }
            if !q.isEmpty {
                let bookTitle = directory.byID[note.bookID]?.title.lowercased() ?? ""
                let chapter = (note.chapterTitle ?? "").lowercased()
                let matches = note.selectedText.lowercased().contains(q)
                    || note.noteContent.lowercased().contains(q)
                    || chapter.contains(q)
                    || bookTitle.contains(q)
                if !matches { return false }
            }
            return true
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if !notes.isEmpty {
                    filterBar
                }

                if filtered.isEmpty {
                    if notes.isEmpty {
                        CrossBookEmptyState(
                            symbol: "note.text",
                            title: "No Notes Yet",
                            subtitle: "Select text while reading and tap \"Note\" to add your first one."
                        )
                    } else {
                        CrossBookEmptyState(
                            symbol: "magnifyingglass",
                            title: "No Matches",
                            subtitle: "Try a different search or filter."
                        )
                    }
                } else {
                    notesList
                }
            }
        }
        .navigationTitle("All Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("All Notes").font(.system(size: 16, weight: .semibold))
                    Text("\(filtered.count) of \(notes.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: filtered.count)
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search notes")
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedColor)
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
            loadNotes()
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteStore.didChangeNotification)) { _ in
            loadNotes()
        }
    }

    // MARK: - Filter bar

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

                Divider().frame(height: 22).padding(.horizontal, 4)

                FilterChip(label: "All", symbol: nil, isSelected: selectedColor == nil) {
                    selectedColor = nil
                }
                ForEach(presentColors, id: \.self) { color in
                    FilterChip(
                        label: color.rawValue.capitalized,
                        accent: color.displayColor,
                        isSelected: selectedColor == color
                    ) {
                        selectedColor = (selectedColor == color) ? nil : color
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - List

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filtered) { note in
                    NoteCrossBookCard(
                        note: note,
                        book: directory.byID[note.bookID]
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        SettingsBookOpener.open(bookID: note.bookID, locatorJSON: note.locatorJSON)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            NoteStore.shared.delete(id: note.id)
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

    private func loadNotes() {
        notes = NoteStore.shared.allNotes()
        // Clear color filter if no longer applicable.
        if let color = selectedColor, !notes.contains(where: { $0.highlightColor == color }) {
            selectedColor = nil
        }
        // Clear book filter for books that no longer have notes.
        bookFilter = bookFilter.filter { id in notes.contains(where: { $0.bookID == id }) }
    }
}

// MARK: - NoteCrossBookCard

private struct NoteCrossBookCard: View {
    let note: Note
    let book: Book?
    let onTap: () -> Void

    private var hasNote: Bool {
        !note.noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(note.highlightColor.displayColor)
                    .frame(width: 3)
                    .padding(.vertical, 14)
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 0) {
                    // Book meta row
                    HStack(spacing: 8) {
                        MiniBookCover(book: book, width: 22, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(book?.title ?? "Unknown Book")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 0) {
                                if let chapter = note.chapterTitle, !chapter.isEmpty {
                                    Text(chapter)
                                        .lineLimit(1)
                                }
                                if let page = note.pageNumber {
                                    let hasChapter = note.chapterTitle?.isEmpty == false
                                    Text((hasChapter ? " · " : "") + "p. \(page)")
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(note.createdAt, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .padding(.trailing, 14)

                    // Selected text (serif)
                    Text(note.selectedText)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 14)
                        .padding(.bottom, hasNote ? 12 : 14)

                    if hasNote {
                        Divider()
                            .padding(.trailing, 14)
                            .opacity(0.5)

                        Text(note.noteContent)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                            .padding(.trailing, 14)
                            .padding(.bottom, 14)
                    }
                }
                .padding(.leading, 12)
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(note.highlightColor.displayColor.opacity(0.05))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(note.highlightColor.displayColor.opacity(0.22), lineWidth: 1)
                )
            )
        }
        .buttonStyle(.plain)
    }
}
