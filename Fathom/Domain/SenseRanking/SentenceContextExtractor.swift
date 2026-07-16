import Foundation
import NaturalLanguage

/// The sentence a selection was made in, with the selection's exact position.
struct SentenceContext: Equatable {
    let sentence: String
    /// Range of the selected word within `sentence`. Always valid for `sentence`.
    let wordRange: Range<String.Index>

    var surfaceWord: String { String(sentence[wordRange]) }
}

/// Turns Readium's raw selection window (`before` + selection + `after`, which
/// can span sentence fragments on both sides) into the actual enclosing
/// sentence plus the precise range of the selected word inside it.
///
/// Because the selection sits exactly between `before` and `after`, the word's
/// position is known — no error-prone substring search.
enum SentenceContextExtractor {

    /// Hard cap on the returned sentence length; beyond this we fall back to a
    /// window around the word (protects the embedding budget and the UI).
    private static let maxSentenceLength = 320

    static func extract(before: String?, selection: String, after: String?) -> SentenceContext? {
        let selection = selection
        guard !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let before = normalizeWhitespace(before ?? "")
        let after = normalizeWhitespace(after ?? "")
        let normalizedSelection = normalizeWhitespace(selection)

        let full = before + normalizedSelection + after
        let selectionStart = full.index(full.startIndex, offsetBy: before.count)
        let selectionEnd = full.index(selectionStart, offsetBy: normalizedSelection.count)

        // Find the sentence containing the selection start.
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = full
        var sentenceRange = tokenizer.tokenRange(at: selectionStart)
        if sentenceRange.isEmpty {
            sentenceRange = full.startIndex..<full.endIndex
        }
        // A selection can straddle a sentence-boundary misdetection; make sure
        // the whole selection is covered.
        if sentenceRange.upperBound < selectionEnd {
            sentenceRange = sentenceRange.lowerBound..<tokenizer.tokenRange(at: selectionEnd).upperBound
        }

        var sentence = String(full[sentenceRange])
        var wordStartOffset = full.distance(from: sentenceRange.lowerBound, to: selectionStart)

        // Trim leading/trailing whitespace while keeping the offset in sync.
        let leadingTrimmed = sentence.prefix(while: { $0.isWhitespace }).count
        sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        wordStartOffset -= leadingTrimmed

        // Degenerate sentence detection (missing punctuation in extracted EPUB
        // text can produce huge "sentences"): clamp to a window around the word.
        if sentence.count > maxSentenceLength {
            let (clamped, newOffset) = clampWindow(
                sentence: sentence, wordStartOffset: wordStartOffset,
                wordLength: normalizedSelection.count
            )
            sentence = clamped
            wordStartOffset = newOffset
        }

        guard wordStartOffset >= 0,
            wordStartOffset + normalizedSelection.count <= sentence.count
        else { return nil }

        let start = sentence.index(sentence.startIndex, offsetBy: wordStartOffset)
        let end = sentence.index(start, offsetBy: normalizedSelection.count)
        guard sentence[start..<end].compare(
            normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame else { return nil }

        return SentenceContext(sentence: sentence, wordRange: start..<end)
    }

    /// Collapses runs of whitespace/newlines to single spaces so character
    /// offsets remain stable and the sentence reads cleanly in the UI.
    private static func normalizeWhitespace(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = false
        for char in text {
            if char.isWhitespace {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(char)
                lastWasSpace = false
            }
        }
        return result
    }

    /// Cuts a word-centred window out of an over-long sentence, snapping to
    /// word boundaries and keeping the word's offset consistent.
    private static func clampWindow(
        sentence: String, wordStartOffset: Int, wordLength: Int
    ) -> (String, Int) {
        let half = maxSentenceLength / 2
        let chars = Array(sentence)
        var start = max(0, wordStartOffset + wordLength / 2 - half)
        var end = min(chars.count, start + maxSentenceLength)
        start = max(0, end - maxSentenceLength)

        // Snap inward to whitespace so we don't cut words in half.
        while start > 0 && start < wordStartOffset && !chars[start].isWhitespace { start += 1 }
        if start > 0 && start < wordStartOffset && chars[start].isWhitespace { start += 1 }
        while end > wordStartOffset + wordLength && end < chars.count && !chars[end - 1].isWhitespace {
            end -= 1
        }

        let clamped = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Recompute offset relative to the clamp, accounting for trimming.
        let prefix = String(chars[start..<min(end, max(start, wordStartOffset))])
        let leadingTrimmed = prefix.prefix(while: { $0.isWhitespace }).count
        return (clamped, wordStartOffset - start - leadingTrimmed)
    }
}
