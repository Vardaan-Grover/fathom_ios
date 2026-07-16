import Combine
import Foundation
import NaturalLanguage
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
    @Published public var rootWordRelationship: String?
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
        let rootWordRelationship: String?
        let sentenceContext: SentenceContext?
    }
    private var navigationStack: [WordSnapshot] = []

    private let service: VocabularyService
    private let repository: VocabularyRepository

    let bookID: UUID?
    let bookTitle: String?
    let chapter: String?
    let pageNumber: Int?
    let locatorJSON: String?
    /// Sentence the word was selected in, with the selection's exact range.
    /// Retained across inflected-form navigation, dropped for arbitrary lookups.
    private(set) var sentenceContext: SentenceContext?
    var contextSentence: String? { sentenceContext?.sentence }
    // The exact surface form of the word as it appears in the context sentence
    // (may differ from `word` when the user navigates to a root/lemma).
    var surfaceWord: String { sentenceContext?.surfaceWord ?? word }

    private let ranker: SenseRanker

    public init(
        word: String,
        language: String = "en",
        bookID: UUID? = nil,
        bookTitle: String? = nil,
        chapter: String? = nil,
        pageNumber: Int? = nil,
        locatorJSON: String? = nil,
        sentenceContext: SentenceContext? = nil,
        service: VocabularyService = .shared,
        repository: VocabularyRepository,  // Injected properly via Container
        ranker: SenseRanker = EmbeddingSenseRanker.shared
    ) {
        self.word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.chapter = chapter
        self.pageNumber = pageNumber
        self.locatorJSON = locatorJSON
        self.sentenceContext = sentenceContext
        self.service = service
        self.repository = repository
        self.ranker = ranker

        Task {
            await checkSavedStatus()
            await fetchDefinition()
            await rankContextually()
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
            if let lemma = lemmatize(word), lemma.lowercased() != word.lowercased() {
                do {
                    let result = try await service.fetchWord(
                        lemma, language: language, includeTranslations: false)
                    self.entry = result
                    self.suggestedRootWord = lemma
                    self.rootWordRelationship = "Lemma form of"
                } catch {
                    self.error = "No definition found for '\(word)'."
                }
            } else {
                self.error = "No definition found for '\(word)'."
            }
        } catch {
            self.error = "Failed to load definition: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func lemmatize(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        let lang = NLLanguage(rawValue: language)
        tagger.setLanguage(lang, range: word.startIndex..<word.endIndex)
        var lemma: String?
        tagger.enumerateTags(in: word.startIndex..<word.endIndex, unit: .word, scheme: .lemma, options: []) { tag, _ in
            if let tag = tag {
                lemma = tag.rawValue
            }
            return false // Stop after the first word
        }
        return lemma
    }

    /// Ranks the entry's senses against the sentence the word was selected in.
    /// Runs automatically once the definition loads; safe to call again (the
    /// ranker caches sense embeddings per word).
    public func rankContextually() async {
        guard let context = sentenceContext, let entry else { return }
        guard !isRanking else { return }
        isRanking = true
        let request = SenseRankingRequest(
            word: entry.word,
            surfaceWord: context.surfaceWord,
            sentence: context.sentence,
            wordRange: context.wordRange,
            entry: entry
        )
        rankedDefinition = await ranker.rank(request)
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
            rootWordRelationship: rootWordRelationship,
            sentenceContext: sentenceContext
        ))

        if !isInflectedForm {
            sentenceContext = nil  // arbitrary lookup — the original sentence no longer applies
        }
        // isInflectedForm: keep sentenceContext — it still points at the word in its sentence
        rankedDefinition = nil

        withAnimation(.easeInOut(duration: 0.22)) {
            canGoBack = true
            word = trimmed
            entry = nil
            error = nil
            isSaved = false
            savedWordID = nil
            suggestedRootWord = nil
            rootWordRelationship = nil
        }

        await checkSavedStatus()
        await fetchDefinition()
        await rankContextually()
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
            rootWordRelationship = snapshot.rootWordRelationship
            sentenceContext = snapshot.sentenceContext
            rankedDefinition = nil
            canGoBack = !navigationStack.isEmpty
        }
        // Sense embeddings are cached, so re-ranking the restored word is cheap.
        Task { await rankContextually() }
    }

    // MARK: - Root word detection

    private static let inflectedFormRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:present participle|past tense(?:\s+and\s+past participle)?|past participle|plural|gerund|comparative|superlative|third.person singular|simple past)(?:\s+(?:and|or)\s+(?:present participle|past tense|past participle|plural|gerund|comparative|superlative|third.person singular|simple past))*\s+of\s+([\w']+(?:\s+[\w']+)?)"#,
        options: .caseInsensitive
    )

    private static let alternativeFormRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b(?:alternative\s+(?:spelling|form|pronunciation)\s+of)\s+([\w']+(?:\s+[\w']+)?)"#,
        options: .caseInsensitive
    )

    private func detectRootWord() {
        guard let entry else {
            suggestedRootWord = nil
            rootWordRelationship = nil
            return
        }
        let definitions = entry.entries.flatMap { $0.senses.map(\.definition) }

        if let regex = Self.inflectedFormRegex {
            for definition in definitions {
                let nsRange = NSRange(definition.startIndex..., in: definition)
                if let match = regex.firstMatch(in: definition, range: nsRange),
                   let rootRange = Range(match.range(at: 1), in: definition)
                {
                    let root = String(definition[rootRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if root.lowercased() != word.lowercased() {
                        suggestedRootWord = root
                        rootWordRelationship = "Inflected form of"
                        return
                    }
                }
            }
        }

        if let regex = Self.alternativeFormRegex {
            for definition in definitions {
                let nsRange = NSRange(definition.startIndex..., in: definition)
                if let match = regex.firstMatch(in: definition, range: nsRange),
                   let rootRange = Range(match.range(at: 1), in: definition)
                {
                    let root = String(definition[rootRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if root.lowercased() != word.lowercased() {
                        suggestedRootWord = root
                        rootWordRelationship = "Alternative spelling/form of"
                        return
                    }
                }
            }
        }

        suggestedRootWord = nil
        rootWordRelationship = nil
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
