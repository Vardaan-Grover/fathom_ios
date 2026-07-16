import SwiftUI

public struct VocabularySheetView: View {
    @StateObject var viewModel: VocabularySheetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingWord = false
    @State private var editText = ""
    @FocusState private var wordFieldFocused: Bool

    public var body: some View {
        sheetContainer
            .edgesIgnoringSafeArea(.bottom)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.automatic)
            .presentationBackground(.clear)
    }

    @ViewBuilder
    private var sheetContainer: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 0) {
                sheetContent
            }
        } else {
            sheetContent
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            inflectedFormBanner
            contextualCard
            contentScrollView
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.suggestedRootWord)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: viewModel.isRanking)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: viewModel.rankedDefinition)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 0) {
            if viewModel.canGoBack {
                Button {
                    viewModel.goBack()
                    isEditingWord = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 32)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if isEditingWord {
                TextField("Look up word…", text: $editText)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                    .focused($wordFieldFocused)
                    .submitLabel(.search)
                    .onSubmit { commitEdit() }
                    .transition(.opacity)

                Spacer(minLength: 12)

                Button {
                    commitEdit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }

                Button {
                    cancelEdit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(.leading, 8)
            } else {
                Button {
                    startEdit()
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Text(viewModel.word)
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                            .contentTransition(.opacity)
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 20) {
                    Button {
                        viewModel.playPronunciation()
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        Task { await viewModel.toggleSave() }
                    } label: {
                        Image(systemName: viewModel.isSaved ? "bookmark.fill" : "bookmark")
                            .font(.body)
                            .foregroundColor(viewModel.isSaved ? .accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .disabled(viewModel.entry == nil && !viewModel.isSaved)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.2), value: isEditingWord)
        .animation(.easeInOut(duration: 0.22), value: viewModel.canGoBack)
    }

    // MARK: - Inflected form banner

    @ViewBuilder
    private var inflectedFormBanner: some View {
        if let root = viewModel.suggestedRootWord {
            Button {
                Task { await viewModel.lookUp(root, isInflectedForm: true) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption2.weight(.semibold))
                    Text(viewModel.rootWordRelationship ?? "Inflected form of")
                        .font(.caption)
                    Text(root)
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.07))
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))

            Divider()
                .transition(.opacity)
        }
    }

    // MARK: - Contextual definition card

    @ViewBuilder
    private var contextualCard: some View {
        if let sentence = viewModel.contextSentence,
           (viewModel.isRanking || viewModel.rankedDefinition != nil) {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isRanking, viewModel.rankedDefinition == nil {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Finding the meaning in this context…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(14)
                    .frame(minHeight: 48)
                    .transition(.opacity)
                } else if let ranked = viewModel.rankedDefinition {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(ranked.isHighConfidence ? "In this context" : "Possibly in this context", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(attributedSentence(sentence: sentence, word: viewModel.surfaceWord, range: viewModel.sentenceContext?.wordRange))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(3)

                        Divider()

                        HStack(alignment: .top, spacing: 8) {
                            Text(ranked.partOfSpeech.uppercased())
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(6)

                            Text(ranked.sense.definition)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(14)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
            }
            .borderBeam(
                border: Color(UIColor.tertiarySystemBackground),
                beam: viewModel.rankedDefinition == nil
                    ? [Color(UIColor.separator)]
                    : (viewModel.rankedDefinition?.isHighConfidence == true
                        ? [Color(hex: "FF6EB4"), Color(hex: "7C86F0"), Color(hex: "4052E3")]
                        : [Color(hex: "8E9AAF"), Color(hex: "B0B8C8"), Color(hex: "8E9AAF")]),
                beamBlur: viewModel.rankedDefinition?.isHighConfidence == true ? 6 : 10,
                cornerRadius: 14
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func attributedSentence(sentence: String, word: String, range: Range<String.Index>?) -> AttributedString {
        var attributed = AttributedString(sentence)
        if let range = range,
           let start = AttributedString.Index(range.lowerBound, within: attributed),
           let end = AttributedString.Index(range.upperBound, within: attributed) {
            attributed[start..<end].font = .subheadline.bold().italic()
            attributed[start..<end].foregroundColor = .primary
        } else if let range = attributed.range(of: word, options: .caseInsensitive) {
            attributed[range].font = .subheadline.bold().italic()
            attributed[range].foregroundColor = .primary
        }
        return attributed
    }

    // MARK: - No definition fallback

    private var noDefinitionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FF6EB4"), Color(hex: "7C86F0")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("No definition found")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Try a different spelling, or tap the pencil icon to look up another word.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 24)
        .transition(.opacity)
    }

    // MARK: - Content

    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.top, 40)
                        Spacer()
                    }
                    .transition(.opacity)
                } else if viewModel.error != nil {
                    noDefinitionView
                } else if let entry = viewModel.entry {
                    if entry.entries.isEmpty {
                        noDefinitionView
                    }
                    ForEach(entry.entries, id: \.partOfSpeech) { dictEntry in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Text(dictEntry.partOfSpeech.uppercased())
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)

                                if let phonetics = dictEntry.pronunciations?
                                    .compactMap(\.text).first
                                {
                                    Text(phonetics)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            ForEach(Array(dictEntry.senses.enumerated()), id: \.offset) { index, sense in
                                senseRow(sense: sense, index: index)
                            }
                        }
                        .padding(.vertical, 8)

                        if dictEntry.partOfSpeech != entry.entries.last?.partOfSpeech {
                            Divider()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
            .animation(.easeInOut(duration: 0.25), value: viewModel.word)
        }
    }

    // MARK: - Sense row

    @ViewBuilder
    private func senseRow(sense: DictionarySense, index: Int) -> some View {
        let isMatch = viewModel.rankedDefinition?.sense.definition == sense.definition
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text("\(index + 1).")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)

                Text(sense.definition)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if isMatch {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            if let examples = sense.examples, !examples.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(examples, id: \.self) { example in
                        Text("\"\(example)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.leading, 20)
                    }
                }
            }
        }
    }

    // MARK: - Edit helpers

    private func startEdit() {
        editText = viewModel.word
        isEditingWord = true
        wordFieldFocused = true
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingWord = false
        wordFieldFocused = false
        guard !trimmed.isEmpty else { return }
        Task { await viewModel.lookUp(trimmed) }
    }

    private func cancelEdit() {
        isEditingWord = false
        wordFieldFocused = false
        editText = ""
    }
}
