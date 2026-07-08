import SwiftUI

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
                ShareSheet(items: [img])
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
        renderer.scale = 2.5
        renderedImage = renderer.uiImage
    }
}
