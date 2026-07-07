import Combine
import Foundation
import ReadiumShared
import SwiftUI
import UIKit

// MARK: - Notification Names

extension Notification.Name {
    static let vocabularyJumpToBook = Notification.Name("VocabularyTab.jumpToBook")
    static let homeScreenOpenReader = Notification.Name("HomeScreen.openReader")
    static let dismissReader = Notification.Name("HomeScreen.dismissReader")
}

// MARK: - Supporting Types

struct BookFilterOption: Identifiable {
    let id: UUID?
    let title: String

    static let all = BookFilterOption(id: nil, title: "All Books")
}

enum StudyPromptStyle: Equatable {
    case fillInBlank
    case definitionToWord
}

struct StudyQuestion: Equatable {
    let savedWord: SavedWord
    let promptText: String
    let promptStyle: StudyPromptStyle
    let choices: [String]
    let correctAnswer: String
}

struct StudySession: Identifiable, Equatable {
    let id: UUID = UUID()
    var questions: [StudyQuestion]
    var currentIndex: Int = 0
    var score: Int = 0

    var isComplete: Bool { currentIndex >= questions.count }
    var currentQuestion: StudyQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }
}

// MARK: - ViewModel

@MainActor
final class VocabularyTabViewModel: ObservableObject {
    @Published var allWords: [SavedWord] = []
    @Published var selectedBookFilter: UUID? = nil
    @Published var searchQuery: String = ""
    @Published var addWordInitialText: String = ""
    @Published var isLoading: Bool = false
    @Published var studySession: StudySession? = nil
    @Published var navigatedToWord: SavedWord? = nil
    @Published var isCardExpanded: Bool = false
    @Published var showAddWord: Bool = false
    @Published var isSearchFocused: Bool = false

    // Card expansion overlay state
    @Published var selectedWord: SavedWord? = nil
    @Published var selectedCardColor: Color = .clear
    @Published var selectedCardFrame: CGRect = .zero
    @Published var isExpanded: Bool = false
    @Published var expandedContentVisible: Bool = false
    @Published var isOverlayVisible: Bool = false
    @Published var expandedWordIndex: Int = 0

    // Actions surfaced from the expanded card
    @Published var showDeleteConfirm: Bool = false
    @Published var wordToShare: SavedWord?
    @Published var isShowingShareSheet: Bool = false
    @Published var wordToEdit: SavedWord? = nil

    private var expandTask: Task<Void, Never>? = nil
    private let vocabularyRepo: VocabularyRepository

    init(vocabularyRepo: VocabularyRepository) {
        self.vocabularyRepo = vocabularyRepo
    }

    // MARK: - Computed

    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var filteredWords: [SavedWord] {
        var words = allWords
        if let bookID = selectedBookFilter {
            words = words.filter { $0.bookID == bookID }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return words }
        let q = query.lowercased()
        return words.filter { word in
            if word.word.lowercased().contains(q) { return true }
            if let data = word.fullDictionaryJSON,
                let entry = try? JSONDecoder().decode(DictionaryWordEntry.self, from: data),
                entry.entries.contains(where: {
                    $0.senses.contains { $0.definition.lowercased().contains(q) }
                })
            {
                return true
            }
            if let title = word.bookTitle, title.lowercased().contains(q) { return true }
            if word.partsOfSpeech.lowercased().contains(q) { return true }
            return false
        }
    }

    var wordCount: Int { filteredWords.count }

    var bookCount: Int { Set(allWords.compactMap(\.bookID)).count }

    var canStudy: Bool { filteredWords.count >= 4 }

    var availableBooks: [BookFilterOption] {
        let uniqueIDs = Array(Set(allWords.compactMap(\.bookID)))
        return uniqueIDs.map { id in
            let title = allWords.first(where: { $0.bookID == id })?.bookTitle ?? "Unknown Book"
            return BookFilterOption(id: id, title: title)
        }
    }

    // MARK: - Actions

    func load() async {
        isLoading = true
        allWords = await vocabularyRepo.listSavedWords()
        isLoading = false
    }

    func removeWord(_ word: SavedWord) async {
        allWords.removeAll { $0.id == word.id }
        await vocabularyRepo.removeSavedWord(id: word.id)
    }

    func togglePin(_ word: SavedWord) async {
        let isCurrentlyPinned = word.pinnedAt != nil
        let newPinnedAt: Date? = isCurrentlyPinned ? nil : Date()

        if let idx = allWords.firstIndex(where: { $0.id == word.id }) {
            var updated = allWords[idx]
            updated.pinnedAt = newPinnedAt
            allWords[idx] = updated
        }

        sortAllWords()
        await vocabularyRepo.setPinnedAt(id: word.id, pinnedAt: newPinnedAt)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func sortAllWords() {
        allWords.sort { a, b in
            switch (a.pinnedAt, b.pinnedAt) {
            case (let aPin?, let bPin?): return aPin > bPin
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.createdAt > b.createdAt
            }
        }
    }

    func navigateTo(_ word: SavedWord) {
        navigatedToWord = word
    }

    func startStudyMode() {
        guard canStudy else { return }
        let session = StudySession(questions: buildQuestions(from: filteredWords))
        studySession = session
    }

    func dismissStudyMode() {
        studySession = nil
    }

    func updateWord(
        _ existing: SavedWord, newText: String, entry: DictionaryWordEntry?,
        contextSentence: String?
    ) async {
        let partsOfSpeech =
            entry.map { e in
                Set(e.entries.map(\.partOfSpeech)).sorted().joined(separator: ", ")
            } ?? existing.partsOfSpeech
        let jsonData = entry.flatMap { try? JSONEncoder().encode($0) }

        let updated = SavedWord(
            id: existing.id,
            word: newText,
            language: existing.language,
            partsOfSpeech: partsOfSpeech,
            bookID: existing.bookID,
            bookTitle: existing.bookTitle,
            chapter: existing.chapter,
            pageNumber: existing.pageNumber,
            locatorJSON: existing.locatorJSON,
            contextSentence: contextSentence,
            fullDictionaryJSON: jsonData ?? existing.fullDictionaryJSON,
            createdAt: existing.createdAt
        )
        if let idx = allWords.firstIndex(where: { $0.id == existing.id }) {
            allWords[idx] = updated
        }
        await vocabularyRepo.updateSavedWord(updated)
    }

    func addManualWord(word: String, entry: DictionaryWordEntry?, contextSentence: String?) async {
        let partsOfSpeech =
            entry.map { e in
                Set(e.entries.map(\.partOfSpeech)).sorted().joined(separator: ", ")
            } ?? ""
        let jsonData = entry.flatMap { try? JSONEncoder().encode($0) }
        let context = contextSentence.flatMap { $0.isEmpty ? nil : $0 }

        let newWord = SavedWord(
            word: word,
            language: "en",
            partsOfSpeech: partsOfSpeech,
            bookID: nil,
            bookTitle: nil,
            chapter: nil,
            pageNumber: nil,
            locatorJSON: nil,
            contextSentence: context,
            fullDictionaryJSON: jsonData
        )
        await vocabularyRepo.addSavedWord(newWord)
        allWords.insert(newWord, at: 0)
    }

    // MARK: - Question Building

    private static let distractorPadding = [
        "ephemeral", "obstinate", "melancholy", "pellucid", "sanguine",
    ]

    private func buildQuestions(from words: [SavedWord]) -> [StudyQuestion] {
        var shuffled = words.shuffled()
        if shuffled.count > 20 { shuffled = Array(shuffled.prefix(20)) }

        return shuffled.compactMap { word in
            let candidates = allWords.filter { $0.id != word.id }.shuffled()
            var distractors = Array(candidates.prefix(3).map { $0.word })
            while distractors.count < 3 {
                let pad = Self.distractorPadding[distractors.count % Self.distractorPadding.count]
                if pad != word.word { distractors.append(pad) }
            }

            let (promptText, style): (String, StudyPromptStyle)

            if let sentence = word.contextSentence,
                let blanked = blankedSentence(sentence: sentence, word: word.word)
            {
                promptText = blanked
                style = .fillInBlank
            } else if let entry = cachedEntry(for: word),
                let def = entry.entries.first?.senses.first?.definition
            {
                promptText = def
                style = .definitionToWord
            } else {
                return nil
            }

            let choices = ([word.word] + distractors).shuffled()
            return StudyQuestion(
                savedWord: word,
                promptText: promptText,
                promptStyle: style,
                choices: choices,
                correctAnswer: word.word
            )
        }
    }

    private func blankedSentence(sentence: String, word: String) -> String? {
        guard let range = sentence.range(of: word, options: .caseInsensitive) else { return nil }

        let before = range.lowerBound
        let after = range.upperBound

        let precedingOK =
            before == sentence.startIndex
            || !sentence[sentence.index(before: before)].isLetter
        let followingOK =
            after == sentence.endIndex
            || !sentence[after].isLetter

        guard precedingOK && followingOK else { return nil }
        return sentence.replacingCharacters(in: range, with: "________")
    }

    func cachedEntry(for word: SavedWord) -> DictionaryWordEntry? {
        guard let data = word.fullDictionaryJSON else { return nil }
        return try? JSONDecoder().decode(DictionaryWordEntry.self, from: data)
    }

    // MARK: - Card Expansion

    var expandedHasPrev: Bool { selectedWord != nil && expandedWordIndex > 0 }
    var expandedHasNext: Bool { selectedWord != nil && expandedWordIndex < filteredWords.count - 1 }

    func expandCard(_ word: SavedWord, frame: CGRect, color: Color) {
        guard selectedWord == nil else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled

        selectedWord = word
        selectedCardColor = color
        selectedCardFrame = frame
        expandedWordIndex = filteredWords.firstIndex(where: { $0.id == word.id }) ?? 0
        isExpanded = false
        expandedContentVisible = false
        isOverlayVisible = true
        isCardExpanded = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if reduceMotion {
            isExpanded = true
            expandedContentVisible = true
            return
        }

        expandTask?.cancel()
        expandTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, selectedWord?.id == word.id else { return }
            withAnimation(.spring(duration: 0.42, bounce: 0.15)) { isExpanded = true }
            withAnimation(.easeOut(duration: 0.22).delay(0.20)) { expandedContentVisible = true }
        }
    }

    func dismissExpanded() {
        expandTask?.cancel()
        expandTask = nil
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if reduceMotion {
            isExpanded = false
            expandedContentVisible = false
            isOverlayVisible = false
            isCardExpanded = false
            selectedWord = nil
            return
        }

        expandedContentVisible = false

        guard isExpanded || isOverlayVisible else {
            isOverlayVisible = false
            isCardExpanded = false
            selectedWord = nil
            return
        }

        withAnimation(.spring(duration: 0.38, bounce: 0.08), completionCriteria: .logicallyComplete)
        {
            isExpanded = false
            isOverlayVisible = false
            isCardExpanded = false
        } completion: {
            self.selectedWord = nil
        }
    }

    func navigateExpanded(by delta: Int) {
        let newIndex = expandedWordIndex + delta
        guard filteredWords.indices.contains(newIndex) else { return }
        expandedWordIndex = newIndex
        let newWord = filteredWords[newIndex]
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(duration: 0.32, bounce: 0.05)) {
            selectedWord = newWord
            selectedCardColor = wordAccentColor(for: newWord)
        }
    }

    func jumpToBook(word: SavedWord) {
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
    func renderAndShare(word: SavedWord) async {
        wordToShare = word
        isShowingShareSheet = true
    }
}
