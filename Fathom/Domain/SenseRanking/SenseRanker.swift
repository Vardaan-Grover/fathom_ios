import Foundation

/// Result of ranking a word's dictionary senses against the sentence it was
/// selected in.
struct RankedDefinition: Equatable {
    let sense: DictionarySense
    let partOfSpeech: String
    /// Calibrated probability-like score in [0, 1] for the winning sense.
    let score: Double
    let isHighConfidence: Bool
}

/// Everything a ranker needs to disambiguate one lookup.
struct SenseRankingRequest {
    /// Dictionary headword (may be a lemma the user navigated to).
    let word: String
    /// Exact form selected in the text (e.g. "running" for headword "run").
    let surfaceWord: String
    /// The sentence the word was selected in.
    let sentence: String
    /// Exact range of `surfaceWord` within `sentence`, when known. Avoids
    /// first-occurrence substring searches for PoS tagging.
    let wordRange: Range<String.Index>?
    let entry: DictionaryWordEntry

    init(
        word: String, surfaceWord: String, sentence: String,
        wordRange: Range<String.Index>? = nil, entry: DictionaryWordEntry
    ) {
        self.word = word
        self.surfaceWord = surfaceWord
        self.sentence = sentence
        self.wordRange = wordRange
        self.entry = entry
    }
}

/// Strategy interface for contextual sense selection, so the embedding
/// ranker can later be swapped for (or arbitrated with) other backends
/// without touching the view model or UI.
protocol SenseRanker: Sendable {
    /// Load models/resources ahead of the first request (e.g. when the
    /// reader opens) so the first lookup doesn't pay the cold-start cost.
    func prewarm() async
    func rank(_ request: SenseRankingRequest) async -> RankedDefinition?
}
