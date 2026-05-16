import Combine
import Foundation
import SwiftUI

@MainActor
final class VocabularySheetViewModel: ObservableObject {
    @Published public var word: String
    @Published public var language: String

    @Published public var entry: DictionaryWordEntry?
    @Published public var isLoading: Bool = false
    @Published public var error: String?

    @Published public var isSaved: Bool = false
    @Published public var suggestedRootWord: String?
    @Published public var canGoBack: Bool = false
    @Published private(set) var rankedDefinition: RankedDefinition?
    @Published private(set) var isRanking: Bool = false
    private var savedWordID: UUID?

    private struct WordSnapshot {
        let word: String
        let entry: DictionaryWordEntry?
        let error: String?
        let isSaved: Bool
        let savedWordID: UUID?
        let suggestedRootWord: String?
        let contextSentence: String?
        let surfaceWord: String
    }
    private var navigationStack: [WordSnapshot] = []

    private let service: VocabularyService
    private let repository: VocabularyRepository

    let bookID: UUID?
    let bookTitle: String?
    let chapter: String?
    let pageNumber: Int?
    let locatorJSON: String?
    private(set) var contextSentence: String?
    // The exact surface form of the word as it appears in contextSentence (may differ
    // from `word` when the user navigates to a root/lemma via the inflected-form banner).
    private(set) var surfaceWord: String = ""

    public init(
        word: String,
        language: String = "en",
        bookID: UUID? = nil,
        bookTitle: String? = nil,
        chapter: String? = nil,
        pageNumber: Int? = nil,
        locatorJSON: String? = nil,
        contextSentence: String? = nil,
        service: VocabularyService = .shared,
        repository: VocabularyRepository  // Injected properly via Container
    ) {
        self.word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        self.surfaceWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.chapter = chapter
        self.pageNumber = pageNumber
        self.locatorJSON = locatorJSON
        self.contextSentence = contextSentence
        self.service = service
        self.repository = repository

        Task {
            await checkSavedStatus()
            await fetchDefinition()
        }
    }

    private func checkSavedStatus() async {
        if let saved = await repository.getSavedWord(word: word, language: language) {
            self.isSaved = true
            self.savedWordID = saved.id
            if let data = saved.fullDictionaryJSON,
                let decoded = try? JSONDecoder().decode(DictionaryWordEntry.self, from: data)
            {
                self.entry = decoded
                detectRootWord()
            }
        } else {
            self.isSaved = false
            self.savedWordID = nil
        }
    }

    public func fetchDefinition() async {
        guard entry == nil else {
            detectRootWord()  // Already loaded from DB
            return
        }

        isLoading = true
        error = nil

        do {
            let result = try await service.fetchWord(
                word, language: language, includeTranslations: false)
            self.entry = result
            detectRootWord()
        } catch VocabularyServiceError.notFound {
            self.error = "No definition found for '\(word)'."
        } catch {
            self.error = "Failed to load definition: \(error.localizedDescription)"
        }

        isLoading = false
    }

    public func rankContextually() async {
        guard #available(iOS 17, *) else { return }
        guard let sentence = contextSentence, let entry else { return }
        guard !isRanking else { return }
        isRanking = true
        rankedDefinition = await ContextualRanker.shared.rank(
            word: word,
            surfaceWord: surfaceWord,
            in: sentence,
            entry: entry
        )
        isRanking = false
    }

    /// Look up a new word, pushing the current state onto the navigation stack.
    /// Pass `isInflectedForm: true` when navigating to a detected root word — the
    /// original context sentence is still meaningful in that case.
    public func lookUp(_ newWord: String, isInflectedForm: Bool = false) async {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != word.lowercased() else { return }

        navigationStack.append(WordSnapshot(
            word: word,
            entry: entry,
            error: error,
            isSaved: isSaved,
            savedWordID: savedWordID,
            suggestedRootWord: suggestedRootWord,
            contextSentence: contextSentence,
            surfaceWord: surfaceWord
        ))

        if !isInflectedForm {
            contextSentence = nil
            surfaceWord = trimmed  // arbitrary lookup — surface form is the new word itself
        }
        // isInflectedForm: keep surfaceWord — it still points to the word in contextSentence
        rankedDefinition = nil

        withAnimation(.easeInOut(duration: 0.22)) {
            canGoBack = true
            word = trimmed
            entry = nil
            error = nil
            isSaved = false
            savedWordID = nil
            suggestedRootWord = nil
        }

        await checkSavedStatus()
        await fetchDefinition()
    }

    /// Restore the previous word from the navigation stack (no network call).
    public func goBack() {
        guard let snapshot = navigationStack.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            word = snapshot.word
            entry = snapshot.entry
            error = snapshot.error
            isSaved = snapshot.isSaved
            savedWordID = snapshot.savedWordID
            suggestedRootWord = snapshot.suggestedRootWord
            contextSentence = snapshot.contextSentence
            surfaceWord = snapshot.surfaceWord
            rankedDefinition = nil
            canGoBack = !navigationStack.isEmpty
        }
    }

    // MARK: - Root word detection

    private static let inflectedFormRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:present participle|past tense(?:\s+and\s+past participle)?|past participle|plural|gerund|comparative|superlative|third.person singular|simple past)(?:\s+(?:and|or)\s+(?:present participle|past tense|past participle|plural|gerund|comparative|superlative|third.person singular|simple past))*\s+of\s+([\w']+(?:\s+[\w']+)?)"#,
        options: .caseInsensitive
    )

    private func detectRootWord() {
        guard let entry else {
            suggestedRootWord = nil
            return
        }
        let definitions = entry.entries.flatMap { $0.senses.map(\.definition) }
        guard let regex = Self.inflectedFormRegex else { return }

        for definition in definitions {
            let nsRange = NSRange(definition.startIndex..., in: definition)
            if let match = regex.firstMatch(in: definition, range: nsRange),
               let rootRange = Range(match.range(at: 1), in: definition)
            {
                let root = String(definition[rootRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if root.lowercased() != word.lowercased() {
                    suggestedRootWord = root
                    return
                }
            }
        }
        suggestedRootWord = nil
    }

    public func toggleSave() async {
        if isSaved {
            if let id = savedWordID {
                await repository.removeSavedWord(id: id)
            }
            self.isSaved = false
            self.savedWordID = nil
        } else {
            guard let entry = entry else { return }
            let newSavedWord = SavedWord(
                entry: entry,
                language: language,
                bookID: bookID,
                bookTitle: bookTitle,
                chapter: chapter,
                pageNumber: pageNumber,
                locatorJSON: locatorJSON,
                contextSentence: contextSentence
            )
            await repository.addSavedWord(newSavedWord)
            self.isSaved = true
            self.savedWordID = newSavedWord.id
        }
    }

    // MARK: - Pronunciation
    public func playPronunciation() {
        // Use AVSpeechSynthesizer for offline/native pronunciation.
        // Map simple language code (e.g., "en" -> "en-US") for the voice.
        let lang = language.count == 2 ? "\(language)-US" : language
        PronunciationService.shared.speak(word, language: lang)
    }

    public func stopPronunciation() {
        PronunciationService.shared.stop()
    }
}
