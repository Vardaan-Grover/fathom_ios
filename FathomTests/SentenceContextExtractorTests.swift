import Foundation
import Testing

@testable import Fathom

struct SentenceContextExtractorTests {

    @Test func extractsEnclosingSentenceFromWindow() throws {
        // Readium windows cut off mid-sentence on both sides.
        let context = try #require(
            SentenceContextExtractor.extract(
                before: "storm had passed. They had a picnic on the ",
                selection: "bank",
                after: " of the river. The next morning everything"
            ))
        #expect(context.sentence == "They had a picnic on the bank of the river.")
        #expect(context.surfaceWord == "bank")
    }

    @Test func targetsSelectedOccurrenceNotFirstMatch() throws {
        // "bank" appears earlier in the window; the selected one must win.
        let context = try #require(
            SentenceContextExtractor.extract(
                before: "The bank statement worried him. He walked to the ",
                selection: "bank",
                after: " of the stream to think."
            ))
        #expect(context.sentence == "He walked to the bank of the stream to think.")
        let offset = context.sentence.distance(
            from: context.sentence.startIndex, to: context.wordRange.lowerBound)
        #expect(offset == 17)  // the second "bank", not the first
    }

    @Test func substringOfAnotherWordIsNotConfused() throws {
        // "art" as a selection where "part" appears earlier in the sentence.
        let context = try #require(
            SentenceContextExtractor.extract(
                before: "For the most part, she preferred ",
                selection: "art",
                after: " to science."
            ))
        #expect(context.surfaceWord == "art")
        let offset = context.sentence.distance(
            from: context.sentence.startIndex, to: context.wordRange.lowerBound)
        #expect(offset == 33)
    }

    @Test func collapsesWhitespaceAndNewlines() throws {
        let context = try #require(
            SentenceContextExtractor.extract(
                before: "The  quick\n\nbrown fox jumped over the ",
                selection: "lazy",
                after: "  dog."
            ))
        #expect(context.sentence == "The quick brown fox jumped over the lazy dog.")
        #expect(context.surfaceWord == "lazy")
    }

    @Test func clampsDegenerateSentencesAroundTheWord() throws {
        // No sentence punctuation at all → one giant "sentence".
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 30)
        let context = try #require(
            SentenceContextExtractor.extract(
                before: filler,
                selection: "serendipity",
                after: " " + filler
            ))
        #expect(context.sentence.count <= 320)
        #expect(context.surfaceWord == "serendipity")
    }

    @Test func missingContextReturnsSelectionSentence() throws {
        let context = try #require(
            SentenceContextExtractor.extract(before: nil, selection: "ephemeral", after: nil))
        #expect(context.sentence == "ephemeral")
        #expect(context.surfaceWord == "ephemeral")
    }

    @Test func emptySelectionReturnsNil() {
        #expect(SentenceContextExtractor.extract(before: "a", selection: "  ", after: "b") == nil)
    }
}
