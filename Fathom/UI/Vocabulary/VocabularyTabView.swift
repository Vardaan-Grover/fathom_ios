import ReadiumShared
import SwiftUI

// MARK: - Card Color Palette

private let wordAccentPalette: [Color] = [
    Color(hex: "B8720A"),  // Burnt Amber
    Color(hex: "2A5E40"),  // Forest Green
    Color(hex: "922840"),  // Deep Rose
    Color(hex: "1C3E6E"),  // Oxford Navy
    Color(hex: "7A3E18"),  // Terracotta
    Color(hex: "4A2472"),  // Deep Violet
    Color(hex: "1A5C6E"),  // Teal
    Color(hex: "6E2A18"),  // Brick Red
    Color(hex: "2E4E1E"),  // Olive
    Color(hex: "8A3A70"),  // Plum
    Color(hex: "1A4A3A"),  // Dark Jade
    Color(hex: "5A3E10"),  // Dark Caramel
    Color(hex: "2A3A6E"),  // Indigo
    Color(hex: "6E4A1A"),  // Saddle Brown
    Color(hex: "3A1A5A"),  // Midnight Purple
    Color(hex: "1E5248"),  // Deep Teal
    Color(hex: "7A2030"),  // Burgundy
    Color(hex: "1E3E28"),  // Dark Emerald
]

// Fallback used by detail/share views where display-order context isn't available
func wordAccentColor(for word: SavedWord) -> Color {
    wordAccentPalette[StableHash.index(of: word.word, count: wordAccentPalette.count)]
}

// Assigns colors in display order, preventing runs of identical colors within a 3-wide window.
func assignMasonryColors(to words: [SavedWord]) -> [UUID: Color] {
    var result: [UUID: Color] = [:]
    var recentSlots: [Int] = []
    for word in words {
        let preferred = StableHash.index(of: word.word, count: wordAccentPalette.count)
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

// Snippets require decoding the word's dictionary JSON blob, and the masonry
// layout asks for one per word per render pass — cache them. Keyed by
// id + modifiedAt so an edited word gets a fresh snippet.
private let definitionSnippetCache = NSCache<NSString, NSString>()

func firstDefinitionSnippet(for word: SavedWord) -> String {
    let key = "\(word.id.uuidString)-\(word.modifiedAt.timeIntervalSince1970)" as NSString
    if let cached = definitionSnippetCache.object(forKey: key) {
        return cached as String
    }

    let snippet: String
    if let data = word.fullDictionaryJSON,
        let entry = try? JSONDecoder().decode(DictionaryWordEntry.self, from: data),
        let def = entry.entries.first?.senses.first?.definition
    {
        snippet = def.count > 120 ? String(def.prefix(120)) + "…" : def
    } else if let ctx = word.contextSentence {
        snippet = ctx.count > 120 ? String(ctx.prefix(120)) + "…" : ctx
    } else {
        snippet = ""
    }

    definitionSnippetCache.setObject(snippet as NSString, forKey: key)
    return snippet
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
            left.append(word)
            leftH += h + 12
        } else {
            right.append(word)
            rightH += h + 12
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
    @FocusState private var isSearchFocused: Bool

    // Context menu state — drives long-press delete confirmations on grid cards
    @State private var contextMenuWord: SavedWord? = nil
    @State private var showContextMenuDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VocabStatsHeader(
                        viewModel: viewModel,
                        onFilterTap: { showBookFilter = true }
                    )
                    .padding(.horizontal, theme.layout.horizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                    VocabSearchBar(text: $viewModel.searchQuery, isFocused: $isSearchFocused)
                        .padding(.horizontal, theme.layout.horizontalPadding)
                        .padding(.bottom, viewModel.isSearchActive && viewModel.filteredWords.isEmpty && !viewModel.isLoading ? 8 : 16)

                    if viewModel.isSearchActive && viewModel.filteredWords.isEmpty && !viewModel.isLoading {
                        searchAddRow
                            .padding(.horizontal, theme.layout.horizontalPadding)
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.filteredWords.isEmpty && !viewModel.isSearchActive {
                        emptyStateView
                    } else if !viewModel.filteredWords.isEmpty {
                        masonryGrid
                            .padding(.horizontal, theme.layout.horizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 100)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.colors.background)
            .toolbarVisibility(.hidden, for: .tabBar)
        }
        .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
        .sheet(isPresented: $showBookFilter) {
            BookFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showAddWord, onDismiss: { viewModel.addWordInitialText = "" }) {
            AddWordSheet(initialWord: viewModel.addWordInitialText) { word, entry, context in
                await viewModel.addManualWord(word: word, entry: entry, contextSentence: context)
            }
        }
        .sheet(item: $viewModel.wordToEdit) { existing in
            AddWordSheet(existingWord: existing) { newText, entry, context in
                await viewModel.updateWord(existing, newText: newText, entry: entry, contextSentence: context)
            }
        }
        .confirmationDialog(
            contextMenuWord.map { "Remove '\($0.word)' from your vocabulary?" } ?? "",
            isPresented: $showContextMenuDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let word = contextMenuWord else { return }
                Task { await viewModel.removeWord(word) }
                contextMenuWord = nil
            }
        }
        .fullScreenCover(item: $viewModel.studySession) { _ in
            StudyModeView(viewModel: viewModel)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.allWords) { _, _ in triggerEntranceAnimations() }
        .onChange(of: viewModel.selectedBookFilter) { _, _ in triggerEntranceAnimations() }
        .onChange(of: isSearchFocused) { _, focused in viewModel.isSearchFocused = focused }
    }

    // MARK: - Search Add Row

    private var searchAddRow: some View {
        let query = viewModel.searchQuery.trimmingCharacters(in: .whitespaces)
        return Button {
            viewModel.addWordInitialText = query
            viewModel.showAddWord = true
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 40, height: 40)
                    HStack(spacing: 1) {
                        Image(systemName: "character")
                            .font(.system(size: 15, weight: .medium))
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \u{201C}\(query)\u{201D}")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Not in your vocabulary yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(searchAddRowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(SpringPressStyle())
    }

    @ViewBuilder
    private var searchAddRowBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.07))
        }
    }

    // MARK: - Masonry Grid

    private var masonryGrid: some View {
        let words = viewModel.filteredWords
        let colors = assignMasonryColors(to: words)
        let cols = masonryColumns(from: words)
        return HStack(alignment: .top, spacing: 12) {
            LazyVStack(spacing: 12) {
                ForEach(cols.left) { word in
                    let color = colors[word.id] ?? wordAccentColor(for: word)
                    VocabWordCard(
                        word: word, cardColor: color, isAppeared: appearedCardIDs.contains(word.id),
                        onExpand: { frame in viewModel.expandCard(word, frame: frame, color: color) },
                        onEdit: { viewModel.wordToEdit = word },
                        onShare: { Task { await viewModel.renderAndShare(word: word) } },
                        onDelete: { contextMenuWord = word; showContextMenuDeleteConfirm = true },
                        onPin: { Task { await viewModel.togglePin(word) } }
                    )
                }
            }
            LazyVStack(spacing: 12) {
                ForEach(cols.right) { word in
                    let color = colors[word.id] ?? wordAccentColor(for: word)
                    VocabWordCard(
                        word: word, cardColor: color, isAppeared: appearedCardIDs.contains(word.id),
                        onExpand: { frame in viewModel.expandCard(word, frame: frame, color: color) },
                        onEdit: { viewModel.wordToEdit = word },
                        onShare: { Task { await viewModel.renderAndShare(word: word) } },
                        onDelete: { contextMenuWord = word; showContextMenuDeleteConfirm = true },
                        onPin: { Task { await viewModel.togglePin(word) } }
                    )
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
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
            Text(
                viewModel.selectedBookFilter != nil
                    ? "No words for this book" : "No saved words yet"
            )
            .font(.system(size: 20, weight: .semibold))
            Text(
                viewModel.selectedBookFilter != nil
                    ? "Try selecting a different book."
                    : "Select any word while reading to look it up and save it here."
            )
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
        let newWords = viewModel.filteredWords.filter { !appearedCardIDs.contains($0.id) }
        for (index, word) in newWords.enumerated() {
            Task { @MainActor in
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

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                ShimmerLabel(
                    text: "\(viewModel.wordCount) words",
                    font: .system(size: 28, weight: .bold, design: .serif),
                    color: theme.colors.primary
                )
                .frame(height: 36)

                Text(subtitleText)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.secondary)
                    .contentTransition(.numericText())
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.8), value: viewModel.bookCount)
            }

            Spacer()

            HStack(spacing: 14) {
                Button(action: onFilterTap) {
                    Image(
                        systemName: viewModel.selectedBookFilter != nil
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                    .font(.system(size: 22))
                    .foregroundStyle(
                        viewModel.selectedBookFilter != nil
                            ? Color.accentColor : theme.colors.secondary)
                }

                Button {
                    viewModel.startStudyMode()
                } label: {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            viewModel.canStudy ? Color.accentColor : theme.colors.secondary)
                }
                .disabled(!viewModel.canStudy)
            }
        }
    }

    private var subtitleText: String {
        let bookText = viewModel.bookCount == 1 ? "1 book" : "\(viewModel.bookCount) books"
        return "across \(bookText)"
    }
}

// Isolated shimmer component — its @State is scoped here, so only this view
// re-renders during the animation, not its parent.
private struct ShimmerLabel: View {
    let text: String
    let font: Font
    let color: Color

    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .overlay(shimmerOverlay)
            .onAppear { play() }
            .onChange(of: text) { play() }
    }

    private func play() {
        phase = 0
        // One-shot sweep: plays once on load and whenever the count changes.
        // No repeatForever means zero continuous CPU/GPU work when idle.
        withAnimation(.linear(duration: 2.0).delay(0.5)) {
            phase = 1.0
        }
    }

    private var shimmerOverlay: some View {
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
            // phase 0 → gradient starts just off the left edge
            // phase 1 → gradient finishes just off the right edge
            .offset(x: phase * w * 1.5 - w * 0.25)
            .allowsHitTesting(false)
        }
        .mask(Text(text).font(font))
        .allowsHitTesting(false)
    }
}

// MARK: - Word Card

/// Holds a card's last-known global frame outside of SwiftUI's state system,
/// so a GeometryReader can keep it up to date during scrolling without
/// triggering a re-render on every frame.
private final class CardFrameHolder {
    var rect: CGRect = .zero
}

struct VocabWordCard: View {
    let word: SavedWord
    let cardColor: Color
    let isAppeared: Bool
    let onExpand: (CGRect) -> Void
    let onEdit: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void

    @Environment(\.appTheme) var theme
    // Plain reference holder (not @State) — the GeometryReader below updates this
    // directly on every layout pass without going through SwiftUI state, so
    // scrolling doesn't trigger a re-render of the card on every frame.
    @State private var frameHolder = CardFrameHolder()

    private var snippet: String { firstDefinitionSnippet(for: word) }

    var body: some View {
        Button {
            onExpand(frameHolder.rect)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(cardColor)

                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.black.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

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
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    bookSource.padding(.top, 6)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)

                // Pin badge
                if word.pinnedAt != nil {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(6)
                        .background(Circle().fill(.white.opacity(0.22)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(SpringPressStyle())
        .contextMenu {
            Button { onPin() } label: {
                Label(
                    word.pinnedAt != nil ? "Unpin" : "Pin",
                    systemImage: word.pinnedAt != nil ? "pin.slash" : "pin"
                )
            }
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { onShare() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 40)
        .scaleEffect(isAppeared ? 1 : 0.92)
        .background(
            GeometryReader { geo -> Color in
                frameHolder.rect = geo.frame(in: .global)
                return Color.clear
            }
        )
    }

    private var posPill: some View {
        let pos = word.partsOfSpeech.components(separatedBy: ", ").first ?? word.partsOfSpeech
        return Text(pos.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.24)))
    }

    @ViewBuilder
    private var bookSource: some View {
        if let title = word.bookTitle {
            HStack(spacing: 4) {
                Image(systemName: "book.closed").font(.system(size: 9))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.65))
        }
    }
}

// MARK: - Expanded Word Card

struct ExpandedWordCard: View {
    let word: SavedWord
    let accentColor: Color
    let entry: DictionaryWordEntry?
    let sourceFrame: CGRect
    let isExpanded: Bool
    let contentVisible: Bool
    let hasPrev: Bool
    let hasNext: Bool
    let onDismiss: () -> Void
    let onNavigatePrev: () -> Void
    let onNavigateNext: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void
    let onJumpToBook: () -> Void

    @Environment(\.appTheme) var theme
    @State private var definitionPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var activeDragAxis: DragAxis? = nil
    @State private var navDirection: Edge? = nil

    private enum DragAxis { case horizontal, vertical }

    private static let headerHeight: CGFloat = 152
    private static let actionsHeight: CGFloat = 58

    private var entries: [DictionaryEntry] { entry?.entries ?? [] }
    private var phoneticText: String? { entries.first?.pronunciations?.compactMap(\.text).first }
    private var canJump: Bool { word.bookID != nil && word.locatorJSON != nil }

    private var contentTransition: AnyTransition {
        guard let dir = navDirection else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: dir).combined(with: .opacity),
            removal: .move(edge: dir == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { screen in
            let target = targetFrame(in: screen.size)
            let arrowY =
                target.minY + Self.headerHeight
                + (target.height - Self.headerHeight - Self.actionsHeight) * 0.4

            ZStack {
                cardShell
                    .frame(
                        width: isExpanded ? target.width : sourceFrame.width,
                        height: isExpanded ? target.height : sourceFrame.height
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: isExpanded ? 26 : 16, style: .continuous)
                    )
                    .shadow(
                        color: .black.opacity(isExpanded ? 0.26 : 0),
                        radius: isExpanded ? 44 : 0,
                        y: isExpanded ? 18 : 0
                    )
                    .position(
                        x: isExpanded ? target.midX : sourceFrame.midX,
                        y: isExpanded ? target.midY : sourceFrame.midY
                    )
                    .offset(x: horizontalDragOffset, y: dragOffset)
                    .gesture(combinedDragGesture)
            }
        }
        .ignoresSafeArea()
        .onChange(of: word.id) { _, _ in /* definitionPage reset handled in parent */ }
        .onChange(of: contentVisible) { _, visible in
            if !visible { navDirection = nil }
        }
    }

    // MARK: - Combined Drag Gesture

    private var combinedDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if activeDragAxis == nil, max(abs(dx), abs(dy)) > 14 {
                    activeDragAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
                }
                switch activeDragAxis {
                case .horizontal:
                    let atEnd = (dx < 0 && !hasNext) || (dx > 0 && !hasPrev)
                    horizontalDragOffset = atEnd ? dx * 0.12 : dx * 0.72
                case .vertical:
                    if dy > 0 { dragOffset = dy * 0.42 }
                case nil: break
                }
            }
            .onEnded { value in
                defer { activeDragAxis = nil }
                switch activeDragAxis {
                case .horizontal:
                    let dx = value.translation.width
                    let vx = value.velocity.width
                    withAnimation(.spring(duration: 0.38, bounce: 0.15)) {
                        horizontalDragOffset = 0
                    }
                    if (dx < -60 || vx < -400) && hasNext {
                        navDirection = .trailing
                        onNavigateNext()
                    } else if (dx > 60 || vx > 400) && hasPrev {
                        navDirection = .leading
                        onNavigatePrev()
                    }
                case .vertical:
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                        // Release the rubber-band with the same spring as the card collapse so
                        // both offset → 0 and position → sourceFrame settle at the same time.
                        withAnimation(.spring(duration: 0.38, bounce: 0.08)) { dragOffset = 0 }
                        onDismiss()
                    } else {
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { dragOffset = 0 }
                    }
                case nil: break
                }
            }
    }

    // MARK: - Shell

    private var cardShell: some View {
        ZStack(alignment: .top) {
            if contentVisible {
                VStack(spacing: 0) {
                    accentColor.frame(height: Self.headerHeight)
                    theme.colors.background
                }
            } else {
                accentColor
            }

            LinearGradient(
                colors: [.white.opacity(0.28), .clear],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.6, y: 0.6)
            )
            .frame(maxWidth: .infinity, maxHeight: contentVisible ? Self.headerHeight : .infinity)

            if contentVisible {
                VStack(spacing: 0) {
                    headerSection.frame(height: Self.headerHeight)

                    Rectangle()
                        .fill(theme.colors.separator.opacity(0.4))
                        .frame(height: 0.5)

                    definitionsArea

                    Rectangle()
                        .fill(theme.colors.separator.opacity(0.4))
                        .frame(height: 0.5)

                    actionsRow.frame(height: Self.actionsHeight)
                }
                .id(word.id)
                .transition(contentTransition)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            Text("\u{201C}")
                .font(.system(size: 128, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.07))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -4, y: -12)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)
                .padding(.trailing, 16)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 7) {
                    Text(word.word)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        ForEach(
                            word.partsOfSpeech.components(separatedBy: ", ").prefix(3),
                            id: \.self
                        ) { pos in
                            Text(pos.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.95))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Capsule().fill(.white.opacity(0.24)))
                        }
                        if let phonetic = phoneticText {
                            Text(phonetic)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.58))
                                .italic()
                        }
                        Spacer(minLength: 0)
                        Button {
                            PronunciationService.shared.speak(word.word)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }

                    if let title = word.bookTitle {
                        HStack(spacing: 5) {
                            Image(systemName: "book.closed.fill").font(.system(size: 10))
                            Text(title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Definitions Area

    @ViewBuilder
    private var definitionsArea: some View {
        if entries.isEmpty {
            noDefinitionView
        } else if entries.count == 1 {
            singleEntryView(entries[0])
        } else {
            pagedEntriesView
        }
    }

    private var noDefinitionView: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.secondary)
            Text("No definition available")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.colors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func singleEntryView(_ dictEntry: DictionaryEntry) -> some View {
        ScrollView(showsIndicators: false) {
            entryContent(dictEntry, showHeader: false)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0))
    }

    private var pagedEntriesView: some View {
        VStack(spacing: 0) {
            GeometryReader { available in
                TabView(selection: $definitionPage) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, dictEntry in
                        entryContent(dictEntry, showHeader: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading
                            )
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: available.size.width, height: available.size.height)
            }

            HStack(spacing: 5) {
                ForEach(entries.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == definitionPage ? accentColor : theme.colors.separator)
                        .frame(width: index == definitionPage ? 18 : 6, height: 6)
                        .animation(.spring(duration: 0.3, bounce: 0.25), value: definitionPage)
                }
            }
            .frame(height: 28)
        }
    }

    private func entryContent(_ dictEntry: DictionaryEntry, showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                HStack(spacing: 8) {
                    Text(dictEntry.partOfSpeech.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accentColor.opacity(0.10)))
                    if let phonetic = dictEntry.pronunciations?.compactMap(\.text).first {
                        Text(phonetic)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.secondary)
                            .italic()
                    }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(dictEntry.senses.prefix(3).enumerated()), id: \.offset) {
                    index, sense in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1).")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(accentColor.opacity(0.7))
                            .frame(width: 18, alignment: .leading)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sense.definition)
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.primary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            if let example = sense.examples?.first {
                                Text("\u{201C}\(example)\u{201D}")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.colors.secondary)
                                    .italic()
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            if dictEntry.senses.count > 3 {
                Text("+ \(dictEntry.senses.count - 3) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.secondary.opacity(0.65))
                    .padding(.leading, 27)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: 10) {
            if canJump {
                Button(action: onJumpToBook) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Jump to Book")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(accentColor))
                }
                .buttonStyle(SpringPressStyle())
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.colors.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.colors.surface))
            }
            .buttonStyle(SpringPressStyle())

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.colors.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.colors.surface))
            }
            .buttonStyle(SpringPressStyle())

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.72))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.red.opacity(0.08)))
            }
            .buttonStyle(SpringPressStyle())
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Geometry

    private func targetFrame(in size: CGSize) -> CGRect {
        let width = size.width - 48
        let height = min(size.height * 0.64, 510)
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2 - 18,
            width: width,
            height: height
        )
    }
}

// MARK: - Search Bar

private struct VocabSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @Environment(\.appTheme) var theme

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                searchContent
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                searchContent
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(theme.colors.surface)
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.42) : Color.clear,
                    lineWidth: 1.5
                )
                .animation(.spring(duration: 0.22, bounce: 0.1), value: isFocused)
        )
        .animation(.spring(duration: 0.22, bounce: 0.1), value: isFocused)
        .animation(.spring(duration: 0.22, bounce: 0.15), value: text.isEmpty)
    }

    private var searchContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isFocused ? Color.accentColor : theme.colors.secondary)
                .animation(.spring(duration: 0.22, bounce: 0.1), value: isFocused)

            TextField("Search words, definitions\u{2026}", text: $text)
                .font(.system(size: 16))
                .foregroundStyle(theme.colors.primary)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.25)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondary.opacity(0.7))
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
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
            Text("Filter by Book").font(theme.typography.headline)
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
                ForEach(viewModel.availableBooks) { option in filterRow(option: option) }
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
