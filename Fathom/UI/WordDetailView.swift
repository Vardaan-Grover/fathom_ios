import ReadiumShared
import SwiftUI

// MARK: - Word Detail View

struct WordDetailView: View {
    let word: SavedWord
    @ObservedObject var viewModel: VocabularyTabViewModel
    @Environment(\.appTheme) var theme
    @Environment(\.dismiss) private var dismiss

    @State private var decodedEntry: DictionaryWordEntry? = nil
    @State private var showDeleteConfirm = false
    @State private var isShowingShareSheet = false
    @State private var shareImage: UIImage? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                contentSection
                    .padding(.top, 24)
                    .padding(.horizontal, theme.layout.horizontalPadding)
                actionsSection
                    .padding(.horizontal, theme.layout.horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
            }
        }
        .background(theme.colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color(.systemRed))
                }
            }
        }
        .confirmationDialog("Remove '\(word.word)' from your vocabulary?",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.removeWord(word)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let img = shareImage {
                ShareLink(
                    item: Image(uiImage: img),
                    preview: SharePreview(word.word, image: Image(uiImage: img))
                )
            }
        }
        .onAppear {
            decodedEntry = viewModel.cachedEntry(for: word)
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        let accent = wordAccentColor(for: word)
        return ZStack(alignment: .bottomLeading) {
            // Base color
            Rectangle()
                .fill(accent)

            // Fade to background at bottom
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, theme.colors.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
            }

            // Decorative serif quotation mark
            Text("\u{201C}")
                .font(.system(size: 180, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.07))
                .offset(x: -12, y: -10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)

            // Content
            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                Text(word.word)
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    possPills
                }

                if let phonetic = decodedEntry?.entries.first?.pronunciations?.compactMap(\.text).first {
                    Text(phonetic)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.65))
                        .italic()
                }
            }
            .padding(.horizontal, theme.layout.horizontalPadding)
            .padding(.bottom, 28)
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private var possPills: some View {
        let parts = word.partsOfSpeech.components(separatedBy: ", ")
        ForEach(parts, id: \.self) { pos in
            Text(pos.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.18)))
        }
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        if let entry = decodedEntry {
            definitionsSection(entry: entry)
        } else {
            Text("No definition cached.")
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondary)
        }

        if let sentence = word.contextSentence {
            contextSection(sentence: sentence)
                .padding(.top, 28)
        }
    }

    private func definitionsSection(entry: DictionaryWordEntry) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(entry.entries, id: \.partOfSpeech) { dictEntry in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(dictEntry.partOfSpeech.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)

                        if let phonetics = dictEntry.pronunciations?.compactMap(\.text).first {
                            Text(phonetics)
                                .font(.subheadline)
                                .foregroundStyle(theme.colors.secondary)
                        }
                    }

                    ForEach(Array(dictEntry.senses.enumerated()), id: \.offset) { index, sense in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(theme.colors.secondary)
                                Text(sense.definition)
                                    .font(theme.typography.body)
                                    .foregroundStyle(theme.colors.primary)
                            }
                            if let examples = sense.examples, !examples.isEmpty {
                                ForEach(examples.prefix(2), id: \.self) { example in
                                    Text("\"\(example)\"")
                                        .font(.subheadline)
                                        .foregroundStyle(theme.colors.secondary)
                                        .italic()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                    }
                }

                if dictEntry.partOfSpeech != entry.entries.last?.partOfSpeech {
                    Divider().opacity(0.5)
                }
            }
        }
    }

    private func contextSection(sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 13, weight: .semibold))
                Text("In Context")
                    .font(theme.typography.headline)
            }
            .foregroundStyle(theme.colors.primary)

            highlightedSentence(sentence: sentence)
                .font(.system(size: 15, design: .serif))
                .lineSpacing(4)

            if let title = word.bookTitle {
                Text(title)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                .fill(theme.colors.surface)
        )
    }

    private func highlightedSentence(sentence: String) -> Text {
        let lower = sentence.lowercased()
        let wordLower = word.word.lowercased()
        guard let range = lower.range(of: wordLower) else {
            return Text(sentence).foregroundColor(Color(.label))
        }
        let before = String(sentence[sentence.startIndex..<range.lowerBound])
        let match = String(sentence[range])
        let after = String(sentence[range.upperBound...])
        return Text(before)
            + Text(match).bold().foregroundColor(Color.accentColor)
            + Text(after)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if word.bookID != nil, word.locatorJSON != nil {
                Button {
                    jumpToBook()
                } label: {
                    Label("Jump to Book", systemImage: "book.open")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(SpringPressStyle())
            }

            Button {
                Task { await renderAndShare() }
            } label: {
                Label("Share Word Card", systemImage: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous)
                            .fill(theme.colors.surface)
                    )
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(SpringPressStyle())
        }
    }

    // MARK: - Actions

    private func jumpToBook() {
        guard let bookID = word.bookID else { return }

        // Pre-save locator so reader opens at the correct position
        if let locatorJSON = word.locatorJSON,
           let locator = try? Locator(jsonString: locatorJSON) {
            ReadingStateStore.shared.saveLocator(locator, forBookID: bookID)
        }

        NotificationCenter.default.post(
            name: .vocabularyJumpToBook,
            object: nil,
            userInfo: ["bookID": bookID, "locatorJSON": word.locatorJSON as Any]
        )
        dismiss()
    }

    @MainActor
    private func renderAndShare() async {
        let card = WordShareCardView(word: word, entry: decodedEntry)
            .frame(width: 390, height: 520)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        if let img = renderer.uiImage {
            shareImage = img
            isShowingShareSheet = true
        }
    }
}

// MARK: - Share Card View (no @Environment — required for ImageRenderer)

struct WordShareCardView: View {
    let word: SavedWord
    let entry: DictionaryWordEntry?

    private var accentColor: Color { wordAccentColor(for: word) }
    private var snippet: String { firstDefinitionSnippet(for: word) }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [accentColor.opacity(0.85), accentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative quotation mark
            Text("\u{201C}")
                .font(.system(size: 220, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.07))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 20, y: -30)

            VStack(spacing: 0) {
                Spacer()

                // POS pill
                let pos = word.partsOfSpeech.components(separatedBy: ", ").first ?? word.partsOfSpeech
                Text(pos.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.18)))
                    .padding(.bottom, 16)

                // Word
                Text(word.word)
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Separator
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 48, height: 1)
                    .padding(.vertical, 20)

                // Definition
                if !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Watermark
                Text("fathom")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
