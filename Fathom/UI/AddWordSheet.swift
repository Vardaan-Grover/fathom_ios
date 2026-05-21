import SwiftUI

struct AddWordSheet: View {
    let onSave: @MainActor (String, DictionaryWordEntry?, String?) async -> Void
    private let isEditMode: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) var theme

    @State private var wordText: String
    @State private var lookedUpWord: String
    @State private var contextText: String
    @State private var definitions: [EditableDefinition]
    @State private var lookupPhase: LookupPhase
    @State private var isSaving = false
    @State private var editingID: UUID? = nil

    @FocusState private var wordFocused: Bool
    @FocusState private var contextFocused: Bool

    init(existingWord: SavedWord? = nil, initialWord: String = "", onSave: @escaping @MainActor (String, DictionaryWordEntry?, String?) async -> Void) {
        self.onSave = onSave
        self.isEditMode = existingWord != nil

        if let word = existingWord {
            _wordText = State(initialValue: word.word)
            _lookedUpWord = State(initialValue: word.word.lowercased())
            _contextText = State(initialValue: word.contextSentence ?? "")

            var defs: [EditableDefinition] = []
            if let data = word.fullDictionaryJSON,
               let entry = try? JSONDecoder().decode(DictionaryWordEntry.self, from: data) {
                for dictEntry in entry.entries {
                    for sense in dictEntry.senses where !sense.definition.isEmpty {
                        defs.append(EditableDefinition(partOfSpeech: dictEntry.partOfSpeech, text: sense.definition))
                    }
                }
            }
            _definitions = State(initialValue: defs)
            _lookupPhase = State(initialValue: defs.isEmpty ? .idle : .done)
        } else {
            _wordText = State(initialValue: initialWord)
            _lookedUpWord = State(initialValue: "")
            _contextText = State(initialValue: "")
            _definitions = State(initialValue: [])
            _lookupPhase = State(initialValue: .idle)
        }
    }

    // MARK: - Types

    private struct EditableDefinition: Identifiable {
        let id = UUID()
        var partOfSpeech: String
        var text: String
        var isSelected: Bool = true
    }

    private enum LookupPhase: Equatable { case idle, loading, done, notFound }

    private static let palette: [Color] = [
        Color(hex: "C4944A"), Color(hex: "4E7C5F"),
        Color(hex: "A85A6A"), Color(hex: "2E5478"), Color(hex: "B07A30"),
    ]

    private static let posOptions = [
        "noun", "verb", "adjective", "adverb", "pronoun",
        "preposition", "phrase", "conjunction", "interjection",
    ]

    // MARK: - Derived

    private var accentColor: Color {
        guard !lookedUpWord.isEmpty else { return Self.palette[0] }
        return Self.palette[abs(lookedUpWord.hashValue) % Self.palette.count]
    }

    private var selectedCount: Int { definitions.filter(\.isSelected).count }

    private var canSave: Bool {
        guard !wordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return false }
        return definitions.contains { $0.isSelected && !$0.text.isEmpty }
    }

    // Stable binding into the definitions array by ID, safe across reordering.
    private func defBinding(_ id: UUID) -> Binding<EditableDefinition> {
        Binding(
            get: {
                definitions.first { $0.id == id }
                    ?? EditableDefinition(partOfSpeech: "noun", text: "")
            },
            set: { newVal in
                if let i = definitions.firstIndex(where: { $0.id == id }) {
                    definitions[i] = newVal
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    wordSection
                    lookupAndAddRow
                    definitionsSection
                    contextSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 60)
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: lookupPhase)
                .animation(.spring(response: 0.38, dampingFraction: 0.85), value: definitions.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.colors.background)
            .navigationTitle(isEditMode ? "Edit Word" : "Add Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.colors.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button { Task { await performSave() } } label: {
                            Text("Save").fontWeight(.semibold)
                        }
                        .disabled(!canSave)
                    }
                }
            }
        }
        .onAppear {
            if !isEditMode {
                wordFocused = true
                if !wordText.isEmpty {
                    Task { await performLookup() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.colors.background)
    }

    // MARK: - Word Section

    private var wordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Word")
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(accentColor)
                .padding(.top, 28)
                .animation(.easeInOut(duration: 0.3), value: accentColor)

            TextField("ephemeral…", text: $wordText)
                .font(.system(size: 38, weight: .bold, design: .serif))
                .foregroundStyle(theme.colors.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($wordFocused)
                .onSubmit { Task { await performLookup() } }
                .onChange(of: wordText) { _, new in
                    // Reset lookup state if the user edits the word after a lookup
                    if new.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != lookedUpWord {
                        lookupPhase = .idle
                        definitions = []
                        lookedUpWord = ""
                    }
                }

            Rectangle()
                .fill(wordFocused ? accentColor : theme.colors.separator)
                .frame(height: wordFocused ? 2 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: wordFocused)
                .animation(.easeInOut(duration: 0.3), value: accentColor)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Lookup + Add Row

    @ViewBuilder
    private var lookupAndAddRow: some View {
        if !wordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(spacing: 12) {
                Button { Task { await performLookup() } } label: {
                    HStack(spacing: 7) {
                        if lookupPhase == .loading {
                            ProgressView().scaleEffect(0.7).tint(.white)
                            Text("Looking up…").font(.system(size: 14, weight: .semibold))
                        } else {
                            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .bold))
                            Text("Look up").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(accentColor))
                    .animation(.easeInOut(duration: 0.3), value: accentColor)
                }
                .buttonStyle(SpringPressStyle())
                .disabled(lookupPhase == .loading)

                Text("or")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.secondary.opacity(0.6))

                Button { addCustomDefinition() } label: {
                    Text("write your own")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accentColor)
                        .underline()
                        .animation(.easeInOut(duration: 0.3), value: accentColor)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.bottom, 28)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Definitions Section

    @ViewBuilder
    private var definitionsSection: some View {
        if !definitions.isEmpty || lookupPhase == .notFound {
            VStack(alignment: .leading, spacing: 0) {
                // Section label
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Definitions")
                        .font(.system(size: 12, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(1.2)
                        .foregroundStyle(accentColor)
                        .animation(.easeInOut(duration: 0.3), value: accentColor)
                    if !definitions.isEmpty {
                        Text("· \(selectedCount) of \(definitions.count) selected")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.secondary.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.bottom, 12)

                // The card
                VStack(spacing: 0) {
                    if lookupPhase == .notFound && definitions.isEmpty {
                        notFoundNotice
                        Divider().opacity(0.25)
                    }

                    ForEach(definitions) { def in
                        definitionRow(def)
                        if def.id != definitions.last?.id {
                            Divider()
                                .padding(.leading, 56)
                                .opacity(0.35)
                        }
                    }

                    Divider().opacity(0.2)
                    addDefinitionRow
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.colors.surface)
                )
            }
            .padding(.bottom, 28)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var notFoundNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.secondary)
            Text("Not found in dictionary — add your own below.")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var addDefinitionRow: some View {
        Button { addCustomDefinition() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                Text("Add definition")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accentColor)
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(SpringPressStyle())
    }

    // MARK: - Definition Row

    @ViewBuilder
    private func definitionRow(_ def: EditableDefinition) -> some View {
        let isEditing = editingID == def.id
        let binding = defBinding(def.id)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {

                // ── Selection toggle ─────────────────────────────────────
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        binding.wrappedValue.isSelected.toggle()
                    }
                } label: {
                    Image(
                        systemName: binding.wrappedValue.isSelected
                            ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.system(size: 20))
                    .foregroundStyle(
                        binding.wrappedValue.isSelected ? accentColor : theme.colors.separator
                    )
                    .frame(width: 28, height: 28)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeInOut(duration: 0.3), value: accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                // ── POS + Definition ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 7) {
                    if isEditing {
                        posChips(binding: binding)
                        definitionEditor(binding: binding)
                    } else {
                        posBadge(pos: binding.wrappedValue.partOfSpeech)
                        definitionText(def: binding.wrappedValue)
                    }
                }

                Spacer(minLength: 0)

                // ── Edit / Delete ────────────────────────────────────────
                VStack(spacing: 4) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            editingID = isEditing ? nil : def.id
                        }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                isEditing ? accentColor : theme.colors.secondary.opacity(0.5)
                            )
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(isEditing ? accentColor.opacity(0.1) : .clear)
                            )
                            .animation(.easeInOut(duration: 0.3), value: accentColor)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            if editingID == def.id { editingID = nil }
                            definitions.removeAll { $0.id == def.id }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red.opacity(0.5))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.red.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isEditing)
    }

    // ── Row sub-views ──────────────────────────────────────────────────────

    private func posBadge(pos: String) -> some View {
        Text(pos.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(accentColor.opacity(0.12)))
            .animation(.easeInOut(duration: 0.3), value: accentColor)
    }

    private func definitionText(def: EditableDefinition) -> some View {
        let isEmpty = def.text.isEmpty
        return Text(isEmpty ? "Tap ✎ to write a definition…" : def.text)
            .font(.system(size: 14))
            .italic(isEmpty)
            .foregroundStyle(
                isEmpty
                    ? theme.colors.secondary.opacity(0.4)
                    : (def.isSelected ? theme.colors.primary : theme.colors.secondary.opacity(0.5))
            )
            .fixedSize(horizontal: false, vertical: true)
    }

    private func posChips(binding: Binding<EditableDefinition>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Self.posOptions, id: \.self) { pos in
                    let isSelected = binding.wrappedValue.partOfSpeech == pos
                    Button {
                        withAnimation(.spring(response: 0.22)) {
                            binding.wrappedValue.partOfSpeech = pos
                        }
                    } label: {
                        Text(pos)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : theme.colors.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(
                                    isSelected ? accentColor : theme.colors.separator.opacity(0.5)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.3), value: accentColor)
                }
            }
        }
    }

    private func definitionEditor(binding: Binding<EditableDefinition>) -> some View {
        ZStack(alignment: .topLeading) {
            if binding.wrappedValue.text.isEmpty {
                Text("Enter definition…")
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(theme.colors.secondary.opacity(0.4))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: binding.text)
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.primary)
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                        .animation(.easeInOut(duration: 0.3), value: accentColor)
                )
        )
    }

    // MARK: - Context Section

    @ViewBuilder
    private var contextSection: some View {
        if !wordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.system(size: 12, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(1.2)
                        .foregroundStyle(theme.colors.secondary)
                    Text("· optional")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.secondary.opacity(0.55))
                }

                ZStack(alignment: .topLeading) {
                    if contextText.isEmpty {
                        Text("Where did you encounter this word?")
                            .font(.system(size: 14))
                            .italic()
                            .foregroundStyle(theme.colors.secondary.opacity(0.45))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $contextText)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primary)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .focused($contextFocused)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    contextFocused ? accentColor.opacity(0.5) : .clear,
                                    lineWidth: 1.5
                                )
                                .animation(.spring(response: 0.3), value: contextFocused)
                                .animation(.easeInOut(duration: 0.3), value: accentColor)
                        )
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func performLookup() async {
        let trimmed = wordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, lookupPhase != .loading else { return }
        wordFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { lookupPhase = .loading }

        do {
            let entry = try await VocabularyService.shared.fetchWord(trimmed)
            var newDefs: [EditableDefinition] = []
            for dictEntry in entry.entries {
                for sense in dictEntry.senses where !sense.definition.isEmpty {
                    newDefs.append(
                        EditableDefinition(partOfSpeech: dictEntry.partOfSpeech, text: sense.definition)
                    )
                }
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                lookedUpWord = trimmed.lowercased()
                definitions = newDefs
                lookupPhase = .done
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                lookedUpWord = trimmed.lowercased()
                lookupPhase = .notFound
            }
        }
    }

    private func addCustomDefinition() {
        wordFocused = false
        let newDef = EditableDefinition(partOfSpeech: "noun", text: "")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            definitions.append(newDef)
            editingID = newDef.id
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func performSave() async {
        let trimmed = wordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let selected = definitions.filter { $0.isSelected && !$0.text.isEmpty }
        let entry: DictionaryWordEntry? = selected.isEmpty ? nil : buildEntry(word: trimmed, from: selected)
        let context = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        await onSave(trimmed, entry, context.isEmpty ? nil : context)

        isSaving = false
        dismiss()
    }

    private func buildEntry(word: String, from defs: [EditableDefinition]) -> DictionaryWordEntry {
        var grouped: [String: [DictionarySense]] = [:]
        for def in defs {
            grouped[def.partOfSpeech, default: []].append(
                DictionarySense(
                    definition: def.text, tags: nil, examples: nil,
                    quotes: nil, synonyms: nil, antonyms: nil,
                    translations: nil, subsenses: nil
                )
            )
        }
        let dictEntries = grouped.map { pos, senses in
            DictionaryEntry(
                language: DictionaryLanguage(code: "en", name: "English"),
                partOfSpeech: pos, pronunciations: nil, forms: nil,
                senses: senses, synonyms: nil, antonyms: nil
            )
        }
        return DictionaryWordEntry(word: word, entries: dictEntries, source: nil)
    }
}
