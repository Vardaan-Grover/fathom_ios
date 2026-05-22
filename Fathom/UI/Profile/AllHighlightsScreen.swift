import SwiftUI

// MARK: - AllHighlightsScreen
//
// Cross-book view of every highlight. Searchable + filterable by book and
// by color.

struct AllHighlightsScreen: View {
    @StateObject private var directory = BookDirectory()

    @State private var highlights: [Highlight] = []
    @State private var search: String = ""
    @State private var selectedColor: HighlightColor? = nil
    @State private var bookFilter: Set<UUID> = []
    @State private var showBookFilter = false

    private var presentColors: [HighlightColor] {
        HighlightColor.allCases.filter { c in highlights.contains { $0.color == c } }
    }

    private var perBookCounts: [UUID: Int] {
        Dictionary(highlights.map { ($0.bookID, 1) }, uniquingKeysWith: +)
    }

    private var filtered: [Highlight] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return highlights.filter { h in
            if let selectedColor, h.color != selectedColor { return false }
            if !bookFilter.isEmpty && !bookFilter.contains(h.bookID) { return false }
            if !q.isEmpty {
                let bookTitle = directory.byID[h.bookID]?.title.lowercased() ?? ""
                if !(h.text.lowercased().contains(q) || bookTitle.contains(q)) {
                    return false
                }
            }
            return true
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if !highlights.isEmpty {
                    filterBar
                }

                if filtered.isEmpty {
                    if highlights.isEmpty {
                        CrossBookEmptyState(
                            symbol: "highlighter",
                            title: "No Highlights Yet",
                            subtitle: "Select text while reading to highlight your first passage."
                        )
                    } else {
                        CrossBookEmptyState(
                            symbol: "magnifyingglass",
                            title: "No Matches",
                            subtitle: "Try a different search or filter."
                        )
                    }
                } else {
                    highlightsList
                }
            }
        }
        .navigationTitle("All Highlights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("All Highlights").font(.system(size: 16, weight: .semibold))
                    Text("\(filtered.count) of \(highlights.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: filtered.count)
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search highlights")
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
            loadHighlights()
        }
        .onReceive(NotificationCenter.default.publisher(for: HighlightStore.didChangeNotification)) { _ in
            loadHighlights()
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

    private var highlightsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { highlight in
                    HighlightCrossBookCard(
                        highlight: highlight,
                        book: directory.byID[highlight.bookID]
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        ProfileBookOpener.open(bookID: highlight.bookID, locatorJSON: highlight.locatorJSON)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            HighlightStore.shared.delete(id: highlight.id)
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

    private func loadHighlights() {
        highlights = HighlightStore.shared.allHighlights()
        if let color = selectedColor, !highlights.contains(where: { $0.color == color }) {
            selectedColor = nil
        }
        bookFilter = bookFilter.filter { id in highlights.contains(where: { $0.bookID == id }) }
    }
}

// MARK: - HighlightCrossBookCard

private struct HighlightCrossBookCard: View {
    let highlight: Highlight
    let book: Book?
    let onTap: () -> Void

    private var meta: LocatorMeta? {
        guard let data = highlight.locatorJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LocatorMeta.self, from: data)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(highlight.color.displayColor)
                    .frame(width: 3)
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
                                if let chapter = meta?.title, !chapter.isEmpty {
                                    Text(chapter).lineLimit(1)
                                }
                                if let position = meta?.locations?.position {
                                    let hasChapter = meta?.title?.isEmpty == false
                                    Text((hasChapter ? " · " : "") + "p. \(position)")
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(highlight.createdAt, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .padding(.trailing, 14)

                    Text(highlight.text)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .fill(highlight.color.displayColor.opacity(0.06))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(highlight.color.displayColor.opacity(0.25), lineWidth: 1)
                )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LocatorMeta: Decodable {
    let title: String?
    let locations: Locations?

    struct Locations: Decodable {
        let position: Int?
        let totalProgression: Double?
    }
}
