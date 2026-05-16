import ReadiumShared
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

// Assigns colors in display order, preventing runs of identical colors within a 3-wide window.
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
        let def = entry.entries.first?.senses.first?.definition
    {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showBookFilter = false
    @State private var appearedCardIDs: Set<UUID> = []

    // Card expansion state
    @State private var selectedWord: SavedWord? = nil
    @State private var selectedCardColor: Color = .clear
    @State private var selectedCardFrame: CGRect = .zero
    @State private var isExpanded = false
    @State private var expandedContentVisible = false
    // Separate from selectedWord so grid can return to normal before the overlay is removed
    @State private var isOverlayVisible = false
    // Cancellable task that fires the expand animation on the frame after appearance
    @State private var expandTask: Task<Void, Never>? = nil
    // Index of the currently expanded word in filteredWords — drives swipe navigation
    @State private var expandedWordIndex: Int = 0

    // Actions triggered from the expanded card
    @State private var showDeleteConfirm = false
    @State private var isShowingShareSheet = false
    @State private var shareImage: UIImage? = nil

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        VocabStatsHeader(
                            viewModel: viewModel,
                            onFilterTap: { showBookFilter = true },
                            onAddTap: { viewModel.showAddWord = true }
                        )
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
                .toolbarVisibility(.hidden, for: .tabBar)
            }
            .blur(radius: isOverlayVisible ? 3 : 0)
            .allowsHitTesting(selectedWord == nil)
            .animation(.spring(duration: 0.42, bounce: 0.05), value: isOverlayVisible)

            // Scrim
            if selectedWord != nil {
                Color.black
                    .opacity(isExpanded ? 0.52 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismissExpanded() }
                    .allowsHitTesting(isExpanded)
                    .animation(.easeInOut(duration: 0.26), value: isExpanded)
            }

            // Expanded card — exit transition crossfades the blank shell into the
            // grid card beneath, hiding the single-frame re-render flash.
            if let word = selectedWord {
                ExpandedWordCard(
                    word: word,
                    accentColor: selectedCardColor,
                    entry: viewModel.cachedEntry(for: word),
                    sourceFrame: selectedCardFrame,
                    isExpanded: isExpanded,
                    contentVisible: expandedContentVisible,
                    hasPrev: expandedHasPrev,
                    hasNext: expandedHasNext,
                    onDismiss: dismissExpanded,
                    onNavigatePrev: { navigateExpanded(by: -1) },
                    onNavigateNext: { navigateExpanded(by: 1) },
                    onDelete: { showDeleteConfirm = true },
                    onShare: { Task { await renderAndShare(word: word) } },
                    onJumpToBook: { jumpToBook(word: word) }
                )
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
        .sheet(isPresented: $showBookFilter) {
            BookFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showAddWord) {
            AddWordSheet { word, entry, context in
                await viewModel.addManualWord(word: word, entry: entry, contextSentence: context)
            }
        }
        .fullScreenCover(item: $viewModel.studySession) { _ in
            StudyModeView(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let img = shareImage {
                ShareLink(
                    item: Image(uiImage: img),
                    preview: SharePreview(selectedWord?.word ?? "", image: Image(uiImage: img))
                )
            }
        }
        .confirmationDialog(
            selectedWord.map { "Remove '\($0.word)' from your vocabulary?" } ?? "",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let word = selectedWord else { return }
                Task {
                    dismissExpanded()
                    await viewModel.removeWord(word)
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.allWords) { _, _ in triggerEntranceAnimations() }
        .onChange(of: viewModel.selectedBookFilter) { _, _ in triggerEntranceAnimations() }
    }

    // MARK: - Masonry Grid

    private var masonryGrid: some View {
        let words = viewModel.filteredWords
        let colors = assignMasonryColors(to: words)
        let cols = masonryColumns(from: words)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                ForEach(cols.left) { word in
                    let color = colors[word.id] ?? wordAccentColor(for: word)
                    VocabWordCard(
                        word: word, cardColor: color, isAppeared: appearedCardIDs.contains(word.id)
                    ) { frame in
                        expandCard(word, frame: frame, color: color)
                    }
                }
            }
            VStack(spacing: 12) {
                ForEach(cols.right) { word in
                    let color = colors[word.id] ?? wordAccentColor(for: word)
                    VocabWordCard(
                        word: word, cardColor: color, isAppeared: appearedCardIDs.contains(word.id)
                    ) { frame in
                        expandCard(word, frame: frame, color: color)
                    }
                }
            }
        }
    }

    // MARK: - Expand / Dismiss

    private func expandCard(_ word: SavedWord, frame: CGRect, color: Color) {
        // Guard against re-entry: prevents double-taps that land before allowsHitTesting
        // updates from corrupting the animation state with two cards' worth of setup.
        guard selectedWord == nil else { return }

        selectedWord = word
        selectedCardColor = color
        selectedCardFrame = frame
        expandedWordIndex = viewModel.filteredWords.firstIndex(where: { $0.id == word.id }) ?? 0
        isExpanded = false
        expandedContentVisible = false
        isOverlayVisible = true
        viewModel.isCardExpanded = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if reduceMotion {
            isExpanded = true
            expandedContentVisible = true
            return
        }

        // Trigger the expand animation on the next frame so SwiftUI has committed
        // the initial (collapsed) state before we animate away from it.
        // The task is cancellable: dismissExpanded() cancels it if the user
        // dismisses before the animation has even started, preventing the
        // onAppear-vs-dismiss race that leaves completionCriteria hanging.
        expandTask?.cancel()
        expandTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, selectedWord?.id == word.id else { return }
            withAnimation(.spring(duration: 0.42, bounce: 0.15)) {
                isExpanded = true
            }
            withAnimation(.easeOut(duration: 0.22).delay(0.20)) {
                expandedContentVisible = true
            }
        }
    }

    private func dismissExpanded() {
        // Cancel any pending expand animation so it can't resurrect isExpanded=true
        // after we've already started collapsing.
        expandTask?.cancel()
        expandTask = nil

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if reduceMotion {
            isExpanded = false
            expandedContentVisible = false
            isOverlayVisible = false
            viewModel.isCardExpanded = false
            selectedWord = nil
            return
        }

        expandedContentVisible = false

        // If the card never finished opening (isExpanded still false), skip the
        // spring entirely — the completion would never fire at its target.
        guard isExpanded || isOverlayVisible else {
            isOverlayVisible = false
            viewModel.isCardExpanded = false
            selectedWord = nil
            return
        }

        withAnimation(.spring(duration: 0.38, bounce: 0.08), completionCriteria: .logicallyComplete)
        {
            isExpanded = false
            isOverlayVisible = false
            viewModel.isCardExpanded = false
        } completion: {
            selectedWord = nil
        }
    }

    private var expandedHasPrev: Bool {
        selectedWord != nil && expandedWordIndex > 0
    }

    private var expandedHasNext: Bool {
        selectedWord != nil && expandedWordIndex < viewModel.filteredWords.count - 1
    }

    private func navigateExpanded(by delta: Int) {
        let newIndex = expandedWordIndex + delta
        guard viewModel.filteredWords.indices.contains(newIndex) else { return }
        expandedWordIndex = newIndex
        let newWord = viewModel.filteredWords[newIndex]
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(duration: 0.32, bounce: 0.05)) {
            selectedWord = newWord
            selectedCardColor = wordAccentColor(for: newWord)
        }
    }

    private func jumpToBook(word: SavedWord) {
        guard let bookID = word.bookID else { return }
        if let locatorJSON = word.locatorJSON,
            let locator = try? Locator(jsonString: locatorJSON)
        {
            ReadingStateStore.shared.saveLocator(locator, forBookID: bookID)
        }
        NotificationCenter.default.post(
            name: .vocabularyJumpToBook,
            object: nil,
            userInfo: ["bookID": bookID, "locatorJSON": word.locatorJSON as Any]
        )
        dismissExpanded()
    }

    @MainActor
    private func renderAndShare(word: SavedWord) async {
        let entry = viewModel.cachedEntry(for: word)
        let card = WordShareCardView(word: word, entry: entry).frame(width: 390, height: 520)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        if let img = renderer.uiImage {
            shareImage = img
            isShowingShareSheet = true
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
    let onAddTap: () -> Void
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
                Button(action: onAddTap) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.colors.secondary)
                }

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

struct VocabWordCard: View {
    let word: SavedWord
    let cardColor: Color
    let isAppeared: Bool
    let onExpand: (CGRect) -> Void

    @Environment(\.appTheme) var theme
    @State private var cardFrame: CGRect = .zero

    private var snippet: String { firstDefinitionSnippet(for: word) }

    var body: some View {
        Button {
            onExpand(cardFrame)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                    .fill(cardColor)

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

                    bookSource.padding(.top, 6)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
        .buttonStyle(SpringPressStyle())
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 40)
        .scaleEffect(isAppeared ? 1 : 0.92)
        .background(
            GeometryReader { geo -> Color in
                let frame = geo.frame(in: .global)
                // Guard prevents the set → re-render → GeometryReader → set cascade.
                if frame != cardFrame {
                    DispatchQueue.main.async { cardFrame = frame }
                }
                return Color.clear
            }
        )
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
        if let title = word.bookTitle {
            HStack(spacing: 4) {
                Image(systemName: "book.closed").font(.system(size: 9))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Expanded Word Card

private struct ExpandedWordCard: View {
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
                colors: [.white.opacity(0.14), .clear],
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
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Capsule().fill(.white.opacity(0.18)))
                        }
                        if let phonetic = phoneticText {
                            Text(phonetic)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.58))
                                .italic()
                        }
                    }

                    if let title = word.bookTitle {
                        HStack(spacing: 5) {
                            Image(systemName: "book.closed.fill").font(.system(size: 10))
                            Text(title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.48))
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
