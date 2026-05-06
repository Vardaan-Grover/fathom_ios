import Foundation
import SwiftSoup

struct ParagraphIndexer {
    nonisolated static func extractParagraphs(
        from html: String,
        bookID: UUID,
        chapterID: UUID?,
        startingAbsoluteIndex: Int
    ) throws -> (paragraphs: [NarrativeParagraph], nextIndex: Int) {

        let doc = try SwiftSoup.parse(html)
        let pNodes = try doc.select("p")

        var paragraphs: [NarrativeParagraph] = []
        var currentAbsoluteIndex = startingAbsoluteIndex
        var currentIndexInChapter = 0

        var seen = Set<String>()
        for node in pNodes {
            let text = try node.text().trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty || isLikelyJunk(text) { continue }

            guard seen.insert(text).inserted else { continue }

            paragraphs.append(
                NarrativeParagraph(
                    id: nil,  // SQLite assigns this on insert
                    bookID: bookID,
                    chapterID: chapterID,
                    indexInChapter: currentIndexInChapter,
                    absoluteIndex: currentAbsoluteIndex,
                    text: text
                ))

            currentAbsoluteIndex += 1
            currentIndexInChapter += 1
        }

        return (paragraphs: paragraphs, currentAbsoluteIndex)
    }

    private nonisolated static func isLikelyJunk(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let lower = trimmed.lowercased()

        if junkExact.contains(lower) { return true }
        if lower.hasPrefix("chapter ") && trimmed.count < 24 { return true }  // heading-only fragments
        if lower.contains("all rights reserved") { return true }
        if lower.contains("copyright") && trimmed.count < 120 { return true }
        if lower.contains("www.") && trimmed.count < 120 { return true }
        if lower.hasSuffix(".com") && trimmed.count < 80 { return true }

        return false
    }

    private nonisolated static let junkExact: Set<String> = [
        "oceanofpdf.com",
        "oceanofpdf",
        "contents",
        "table of contents",
        "project gutenberg",
        "gutenberg"
    ]
}
