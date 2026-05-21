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
    @State private var isShowingSharePreview = false

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
        .confirmationDialog(
            "Remove '\(word.word)' from your vocabulary?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.removeWord(word)
                    dismiss()
                }
            }
        }
        .onAppear {
            decodedEntry = viewModel.cachedEntry(for: word)
        }
        .sheet(isPresented: $isShowingSharePreview) {
            WordSharePreviewSheet(word: word, entry: decodedEntry)
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

                if let phonetic = decodedEntry?.entries.first?.pronunciations?.compactMap(\.text)
                    .first
                {
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
                            RoundedRectangle(
                                cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous
                            )
                            .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(SpringPressStyle())
            }

            Button {
                isShowingSharePreview = true
            } label: {
                Label("Share Word Card", systemImage: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(
                            cornerRadius: theme.layout.cornerRadiusLarge, style: .continuous
                        )
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
            let locator = try? Locator(jsonString: locatorJSON)
        {
            ReadingStateStore.shared.saveLocator(locator, forBookID: bookID)
        }

        NotificationCenter.default.post(
            name: .vocabularyJumpToBook,
            object: nil,
            userInfo: ["bookID": bookID, "locatorJSON": word.locatorJSON as Any]
        )
        dismiss()
    }

}

// MARK: - Share Card View (no @Environment — used with ImageRenderer)
//
// Size is controlled entirely by the caller via ImageRenderer.proposedSize.
// No internal frame constraints — keeps rendering predictable.

struct WordShareCardView: View {
    let word: SavedWord
    let entry: DictionaryWordEntry?
    var definitionOverride: String? = nil

    // All colours hardcoded for light mode — @Environment unavailable in ImageRenderer.
    private static let paper = Color(red: 0.965, green: 0.949, blue: 0.922)
    private static let ink = Color(red: 0.11, green: 0.09, blue: 0.07)
    private static let inkLight = Color(red: 0.44, green: 0.40, blue: 0.36)
    private static let ruleCol = Color(red: 0.70, green: 0.65, blue: 0.59)

    private var definition: String {
        if let ov = definitionOverride, !ov.isEmpty {
            return ov.count > 130 ? String(ov.prefix(130)) + "…" : ov
        }
        if let e = entry, let def = e.entries.first?.senses.first?.definition {
            return def.count > 130 ? String(def.prefix(130)) + "…" : def
        }
        return firstDefinitionSnippet(for: word)
    }

    private var phonetic: String? {
        entry?.entries.first?.pronunciations?.compactMap(\.text).first
    }

    private var pos: String {
        word.partsOfSpeech.components(separatedBy: ", ").first ?? word.partsOfSpeech
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top rules
            Self.ruleCol.frame(maxWidth: .infinity).frame(height: 2)

            // POS · phonetic
            HStack(spacing: 0) {
                Text(pos.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(Self.inkLight)
                if let ph = phonetic {
                    Text("  ·  \(ph)")
                        .font(.system(size: 12, weight: .regular))
                        .italic()
                        .foregroundStyle(Self.inkLight)
                }
                Spacer()
            }
            .padding(.top, 26)
            .padding(.horizontal, 30)

            // Word — the typography hero
            Text(word.word)
                .font(.system(size: 76, weight: .bold, design: .serif))
                .foregroundStyle(Self.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.42)
                .padding(.top, 8)
                .padding(.horizontal, 30)

            // Mid rule
            Self.ruleCol.frame(maxWidth: .infinity).frame(height: 1)
                .padding(.top, 22)

            // Definition
            if !definition.isEmpty {
                Text(definition)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Self.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(5)
                    .lineLimit(5)
                    .padding(.top, 18)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 0)

            // Bottom rule
            Self.ruleCol.frame(maxWidth: .infinity).frame(height: 1)

            // Footer
            HStack {
                Text("fathom")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Self.inkLight)
                Spacer()
                Text("expand your vocabulary")
                    .font(.system(size: 10, weight: .regular))
                    .tracking(0.5)
                    .foregroundStyle(Self.inkLight.opacity(0.7))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 30)

            // Closing rule
            Self.ruleCol.frame(maxWidth: .infinity).frame(height: 3)
        }
        .background(Self.paper)
    }
}

// MARK: - Share Preview Sheet
// Plain VStack — no NavigationStack inside a sheet (causes blank rendering on iOS 26).

struct WordSharePreviewSheet: View {
    let word: SavedWord
    let entry: DictionaryWordEntry?

    @State private var selectedIndex = 0
    @State private var renderedImage: UIImage? = nil
    @State private var isSharePresented = false
    @Environment(\.dismiss) private var dismiss

    private var resolvedEntry: DictionaryWordEntry? {
        entry
            ?? word.fullDictionaryJSON.flatMap {
                try? JSONDecoder().decode(DictionaryWordEntry.self, from: $0)
            }
    }

    private var senses: [(pos: String, definition: String)] {
        resolvedEntry?.entries.flatMap { e in
            e.senses.map { (e.partOfSpeech, $0.definition) }
        } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    previewSection

                    if senses.count > 1 {
                        definitionPicker
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            shareButtonSection
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .task { await render() }
        .onChange(of: selectedIndex) { _, _ in Task { await render() } }
        .sheet(isPresented: $isSharePresented) {
            if let img = renderedImage {
                ActivityView(image: img)
                    .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Share Card")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer()
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color(.quaternarySystemFill))
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var previewSection: some View {
        Group {
            if let img = renderedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.2)
                    )
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 12)
    }

    private var definitionPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SELECT DEFINITION")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                ForEach(Array(senses.enumerated()), id: \.offset) { idx, sense in
                    definitionRow(idx: idx, sense: sense)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func definitionRow(idx: Int, sense: (pos: String, definition: String)) -> some View {
        let sel = selectedIndex == idx
        return Button {
            #if os(iOS)
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            #endif
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedIndex = idx
            }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                // Animated Checkbox
                ZStack {
                    Circle()
                        .stroke(
                            sel ? Color.accentColor : Color(.systemGray4), lineWidth: sel ? 6 : 1.5
                        )
                        .frame(width: 22, height: 22)
                    if sel {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(sense.pos.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(sel ? Color.accentColor : .secondary)

                    Text(sense.definition)
                        .font(.system(size: 16, weight: .regular, design: .default))
                        .foregroundStyle(sel ? Color.primary : Color.primary.opacity(0.8))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        sel
                            ? Color.accentColor.opacity(0.08)
                            : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        sel ? Color.accentColor.opacity(0.5) : Color(.separator).opacity(0.5),
                        lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var shareButtonSection: some View {
        VStack {
            Button {
                isSharePresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .bold))
                    Text("Share Card")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    renderedImage != nil ? Color.accentColor : Color.accentColor.opacity(0.4)
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(
                    color: renderedImage != nil ? Color.accentColor.opacity(0.3) : .clear,
                    radius: 12, x: 0, y: 6)
            }
            .disabled(renderedImage == nil)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
    }

    @MainActor
    private func render() async {
        let def: String? =
            senses.indices.contains(selectedIndex) ? senses[selectedIndex].definition : nil
        let card = WordShareCardView(word: word, entry: resolvedEntry, definitionOverride: def)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: 500, height: 500)
        renderer.scale = 3.0
        renderedImage = renderer.uiImage
    }
}

// MARK: - UIActivityViewController sheet wrapper

private struct ActivityView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
