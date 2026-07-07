import Foundation
import Testing

@testable import Fathom

/// ParagraphIndexer feeds the narrative context database — index continuity
/// and junk filtering directly affect AI context resolution.
struct ParagraphIndexerTests {

    @Test func extractsParagraphsWithContinuousIndices() throws {
        let html = """
            <html><body>
            <p>The first paragraph of the chapter, long enough to keep.</p>
            <p>The second paragraph follows with more narrative text.</p>
            </body></html>
            """
        let result = try ParagraphIndexer.extractParagraphs(
            from: html, bookID: UUID(), chapterID: UUID(), startingAbsoluteIndex: 5)

        #expect(result.paragraphs.count == 2)
        #expect(result.paragraphs[0].absoluteIndex == 5)
        #expect(result.paragraphs[1].absoluteIndex == 6)
        #expect(result.paragraphs[0].indexInChapter == 0)
        #expect(result.paragraphs[1].indexInChapter == 1)
        #expect(result.nextIndex == 7)
    }

    @Test func normalizesWhitespaceAndSpecialCharacters() throws {
        // Non-breaking space and soft hyphen must normalize the same way the
        // reader-side probe normalization does, or lookups won't match.
        let html = "<p>First&nbsp;para\u{00AD}graph   with \n odd    spacing.</p>"
        let result = try ParagraphIndexer.extractParagraphs(
            from: html, bookID: UUID(), chapterID: nil, startingAbsoluteIndex: 0)

        #expect(result.paragraphs.count == 1)
        #expect(result.paragraphs[0].text == "First paragraph with odd spacing.")
    }

    @Test func filtersJunkParagraphs() throws {
        let html = """
            <html><body>
            <p>OceanofPDF.com</p>
            <p>Chapter 3</p>
            <p>Copyright © 2020 by Somebody. All rights reserved.</p>
            <p>Real story content that should definitely survive the filter.</p>
            </body></html>
            """
        let result = try ParagraphIndexer.extractParagraphs(
            from: html, bookID: UUID(), chapterID: nil, startingAbsoluteIndex: 0)

        #expect(result.paragraphs.count == 1)
        #expect(result.paragraphs[0].text.hasPrefix("Real story content"))
    }

    @Test func deduplicatesRepeatedParagraphs() throws {
        let html = """
            <p>An identical paragraph repeated by a malformed EPUB layout.</p>
            <p>An identical paragraph repeated by a malformed EPUB layout.</p>
            <p>A different paragraph that should also be kept in the output.</p>
            """
        let result = try ParagraphIndexer.extractParagraphs(
            from: html, bookID: UUID(), chapterID: nil, startingAbsoluteIndex: 0)

        #expect(result.paragraphs.count == 2)
    }
}
