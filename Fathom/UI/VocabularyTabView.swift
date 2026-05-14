import SwiftUI

// MARK: - Card Color Palette

private let wordAccentPalette: [Color] = [
    Color(hex: "C4944A"),  // Sepia Ochre
    Color(hex: "4E7C5F"),  // Scholar Green
    Color(hex: "A85A6A"),  // Faded Rose
    Color(hex: "2E5478"),  // Oxford Blue
    Color(hex: "B07A30"),  // Amber Dusk
]

// Fallback used by detail/share views where display-order context isn't available
func wordAccentColor(for word: SavedWord) -> Color {
    wordAccentPalette[abs(word.word.hashValue) % wordAccentPalette.count]
}

// Assigns colors to words in display order, ensuring no slot repeats within
// a window of 3 — prevents runs of identical colors across adjacent cards.
func assignMasonryColors(to words: [SavedWord]) -> [UUID: Color] {
    var result: [UUID: Color] = [:]
    var recentSlots: [Int] = []
    for word in words {
        let preferred = abs(word.word.hashValue) % wordAccentPalette.count
        var slot = preferred
        var tries = 0
        while recentSlots.suffix(3).contains(slot) && tries < wordAccentPalette.count {
            slot = (slot + 1) % wordAccentPalette.count
            tries += 1
        }
        result[word.id] = wordAccentPalette[slot]
        recentSlots.append(slot)
    }
    return result
}

func firstDefinitionSnippet(for word: SavedWord) -> String {
    if let data = word.fullDictionaryJSON,
       let entry = try? JSONDecoder().decode(DictionaryWordEntry.self, from: data),
       let def = entry.entries.first?.senses.first?.definition {
        return def.count > 120 ? String(def.prefix(120)) + "…" : def
    }
    if let ctx = word.contextSentence {
        return ctx.count > 120 ? String(ctx.prefix(120)) + "…" : ctx
    }
    return ""
}

func estimatedCardHeight(for word: SavedWord) -> CGFloat {
    let snippet = firstDefinitionSnippet(for: word)
    let charsPerLine: CGFloat = 26
    let snippetLines = max(1, CGFloat(snippet.count) / charsPerLine)
    let wordLines = max(1, CGFloat(word.word.count) / 13)
    let base: CGFloat = 76
    return min(220, base + snippetLines * 18 + wordLines * 22)
}

private func masonryColumns(from words: [SavedWord]) -> (left: [SavedWord], right: [SavedWord]) {
    var left: [SavedWord] = []
    var right: [SavedWord] = []
    var leftH: CGFloat = 0
    var rightH: CGFloat = 0
    for word in words {
        let h = estimatedCardHeight(for: word)
        if leftH <= rightH {
            left.append(word); leftH += h + 12
        } else {
            right.append(word); rightH += h + 12
        }
    }
    return (left, right)
}

// MARK: - Main View

struct VocabularyTabView: View {
    @ObservedObject var viewModel: VocabularyTabViewModel
    @Environment(\.appTheme) var theme

    @State private var showBookFilter = false
    @State private var appearedCardIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VocabStatsHeader(viewModel: viewModel, onFilterTap: { showBookFilter = true })
                        .padding(.horizontal, theme.layout.horizontalPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.filteredWords.isEmpty {
                        emptyStateView
                    } else {
                        masonryGrid
                            .padding(.horizontal, theme.layout.horizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 100)
                    }
                }
            }
            .background(theme.colors.background)
            .navigationDestination(item: $viewModel.navigatedToWord) { word in
                WordDetailView(word: word, viewModel: viewModel)
            }
            .toolbarVisibility(.hidden, for: .tabBar)
        }
        .sheet(isPresented: $showBookFilter) {
            BookFilterSheet(viewModel: viewModel)
        }
        .fullScreenCover(item: $viewModel.studySession) { _ in
            StudyModeView(viewModel: viewModel)
        }
        .task { await viewModel.load() }
        // Trigger for both initial load and newly saved words
        .onChange(of: viewModel.allWords) { _, _ in
            triggerEntranceAnimations()
        }
        .onChange(of: viewModel.selectedBookFilter) { _, _ in
            triggerEntranceAnimations()
        }
    }

    // MARK: - Masonry Grid

    private var masonryGrid: some View {
        let words = viewModel.filteredWords
        let colors = assignMasonryColors(to: words)
        let cols = masonryColumns(from: words)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                ForEach(cols.left) { word in
                    VocabWordCard(
                        word: word,
                        cardColor: colors[word.id] ?? wordAccentColor(for: word),
                        isAppeared: appearedCardIDs.contains(word.id)
                    ) {
                        viewModel.navigateTo(word)
                    }
                }
            }
            VStack(spacing: 12) {
                ForEach(cols.right) { word in
                    VocabWordCard(
                        word: word,
                        cardColor: colors[word.id] ?? wordAccentColor(for: word),
                        isAppeared: appearedCardIDs.contains(word.id)
                    ) {
                        viewModel.navigateTo(word)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 96, height: 96)
                Image(systemName: "character.book.closed")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(viewModel.selectedBookFilter != nil ? "No words for this book" : "No saved words yet")
                .font(.system(size: 20, weight: .semibold))
            Text(viewModel.selectedBookFilter != nil
                 ? "Try selecting a different book."
                 : "Select any word while reading to look it up and save it here.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
        .padding(.top, 80)
    }

    // MARK: - Entrance Animation

    private func triggerEntranceAnimations() {
        // Only animate words not already visible — handles both initial load and new arrivals
        let newWords = viewModel.filteredWords.filter { !appearedCardIDs.contains($0.id) }
        for (index, word) in newWords.enumerated() {
            Task { @MainActor in
                // 80ms stagger — noticeable cascade without feeling slow
                try? await Task.sleep(nanoseconds: UInt64(index) * 80_000_000)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
                    appearedCardIDs.insert(word.id)
                }
            }
        }
    }
}

// MARK: - Stats Header

private struct VocabStatsHeader: View {
    @ObservedObject var viewModel: VocabularyTabViewModel
    let onFilterTap: () -> Void
    @Environment(\.appTheme) var theme

    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                shimmerWordCount
                    .frame(height: 36)
                Text(subtitleText)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.bookCount)
            }

            Spacer()

            HStack(spacing: 14) {
                Button(action: onFilterTap) {
                    Image(systemName: viewModel.selectedBookFilter != nil
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(viewModel.selectedBookFilter != nil
                                         ? Color.accentColor : theme.colors.secondary)
                }

                Button {
                    viewModel.startStudyMode()
                } label: {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(viewModel.canStudy ? Color.accentColor : theme.colors.secondary)
                }
                .disabled(!viewModel.canStudy)
            }
        }
    }

    private var subtitleText: String {
        let bookText = viewModel.bookCount == 1 ? "1 book" : "\(viewModel.bookCount) books"
        return "across \(bookText)"
    }

    private var shimmerWordCount: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: false)) { context in
            let _ = context.date  // force re-evaluation each frame
            shimmerText
                .onAppear { shimmerPhase = 0 }
        }
    }

    private var shimmerText: some View {
        Text("\(viewModel.wordCount) words")
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(theme.colors.primary)
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.55), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.5)
                    .offset(x: shimmerPhase - w * 0.25)
                    .onAppear {
                        withAnimation(.linear(duration: 2.2).delay(0.6).repeatForever(autoreverses: false)) {
                            shimmerPhase = w * 1.5
                        }
                    }
                    .allowsHitTesting(false)
                }
                .mask(
                    Text("\(viewModel.wordCount) words")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                )
            )
    }
}

// MARK: - Word Card

struct VocabWordCard: View {
    let word: SavedWord
    let cardColor: Color
    let isAppeared: Bool
    let action: () -> Void
    @Environment(\.appTheme) var theme

    private var snippet: String { firstDefinitionSnippet(for: word) }
    private var accentColor: Color { cardColor }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(accentColor)

                // Subtle inner gradient for depth
                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 6) {
                    posPill

                    Text(word.word)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !snippet.isEmpty {
                        Text(snippet)
                            .font(theme.typography.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    bookSource
                        .padding(.top, 6)
                }
                // Natural vertical padding — no Spacer, so height matches content
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
        .buttonStyle(SpringPressStyle())
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 40)
        .scaleEffect(isAppeared ? 1 : 0.92)
    }

    private var posPill: some View {
        let pos = word.partsOfSpeech.components(separatedBy: ", ").first ?? word.partsOfSpeech
        return Text(pos.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.18)))
    }

    @ViewBuilder
    private var bookSource: some View {
        if let chapter = word.chapter {
            HStack(spacing: 4) {
                Image(systemName: "book.closed")
                    .font(.system(size: 9))
                Text(chapter)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Book Filter Sheet

struct BookFilterSheet: View {
    @ObservedObject var viewModel: VocabularyTabViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack(spacing: 0) {
            sheetHandle
            sheetHeader
            Divider().opacity(0.4)
            filterList
        }
        .presentationDetents([.fraction(0.45)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private var sheetHandle: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var sheetHeader: some View {
        HStack {
            Text("Filter by Book")
                .font(theme.typography.headline)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var filterList: some View {
        ScrollView {
            VStack(spacing: 0) {
                filterRow(option: .all)
                ForEach(viewModel.availableBooks) { option in
                    filterRow(option: option)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func filterRow(option: BookFilterOption) -> some View {
        let isSelected = viewModel.selectedBookFilter == option.id

        return Button {
            viewModel.selectedBookFilter = option.id
            dismiss()
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                Text(option.title)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primary)
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(SpringPressStyle())
    }
}
