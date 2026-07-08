import SwiftUI

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
            masonryColumn(cols.left, colors: colors)
            masonryColumn(cols.right, colors: colors)
        }
    }

    private func masonryColumn(_ words: [SavedWord], colors: [UUID: Color]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(words) { word in
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

    // MARK: - Loading / Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

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
