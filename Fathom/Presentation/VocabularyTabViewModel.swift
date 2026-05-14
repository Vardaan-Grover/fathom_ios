import Combine
import Foundation
import UIKit

// MARK: - Notification Names

extension Notification.Name {
    static let vocabularyJumpToBook = Notification.Name("VocabularyTab.jumpToBook")
    static let homeScreenOpenReader = Notification.Name("HomeScreen.openReader")
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
    @Published var isLoading: Bool = false
    @Published var studySession: StudySession? = nil
    @Published var navigatedToWord: SavedWord? = nil

    private let vocabularyRepo: VocabularyRepository
    private var hasPlayedLoadHaptics = false

    init(vocabularyRepo: VocabularyRepository) {
        self.vocabularyRepo = vocabularyRepo
    }

    // MARK: - Computed

    var filteredWords: [SavedWord] {
        guard let bookID = selectedBookFilter else { return allWords }
        return allWords.filter { $0.bookID == bookID }
    }

    var wordCount: Int { filteredWords.count }

    var bookCount: Int { Set(allWords.compactMap(\.bookID)).count }

    var canStudy: Bool { filteredWords.count >= 4 }

    var availableBooks: [BookFilterOption] {
        let uniqueIDs = Array(Set(allWords.compactMap(\.bookID)))
        return uniqueIDs.map { id in
            let title = allWords.first(where: { $0.bookID == id })?.chapter
                .flatMap { $0.components(separatedBy: " — ").first }
                ?? "Unknown Book"
            return BookFilterOption(id: id, title: title)
        }
    }

    // MARK: - Actions

    func load() async {
        isLoading = true
        allWords = await vocabularyRepo.listSavedWords()
        isLoading = false
        if !allWords.isEmpty && !hasPlayedLoadHaptics {
            hasPlayedLoadHaptics = true
            fireLoadHaptics()
        }
    }

    func removeWord(_ word: SavedWord) async {
        allWords.removeAll { $0.id == word.id }
        await vocabularyRepo.removeSavedWord(id: word.id)
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

    // MARK: - Haptics

    private func fireLoadHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        Task { @MainActor in
            generator.impactOccurred()
            try? await Task.sleep(nanoseconds: 80_000_000)
            generator.impactOccurred()
            try? await Task.sleep(nanoseconds: 80_000_000)
            generator.impactOccurred()
        }
    }

    // MARK: - Question Building

    private static let distractorPadding = ["ephemeral", "obstinate", "melancholy", "pellucid", "sanguine"]

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
               let blanked = blankedSentence(sentence: sentence, word: word.word) {
                promptText = blanked
                style = .fillInBlank
            } else if let entry = cachedEntry(for: word),
                      let def = entry.entries.first?.senses.first?.definition {
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

        let precedingOK = before == sentence.startIndex
            || !sentence[sentence.index(before: before)].isLetter
        let followingOK = after == sentence.endIndex
            || !sentence[after].isLetter

        guard precedingOK && followingOK else { return nil }
        return sentence.replacingCharacters(in: range, with: "________")
    }

    func cachedEntry(for word: SavedWord) -> DictionaryWordEntry? {
        guard let data = word.fullDictionaryJSON else { return nil }
        return try? JSONDecoder().decode(DictionaryWordEntry.self, from: data)
    }
}
