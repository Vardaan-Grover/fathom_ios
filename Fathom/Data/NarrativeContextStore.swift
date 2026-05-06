import Foundation
import GRDB

actor NarrativeContextStore {
    static let shared = NarrativeContextStore(dbQueue: DatabaseManager.shared.dbQueue)

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func hasParagraphs(for bookID: UUID) async -> Bool {
        do {
            return try await dbQueue.read { db in
                let count = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM paragraphs WHERE bookID = ?",
                    arguments: [bookID]
                ) ?? 0
                return count > 0
            }
        } catch {
            return false
        }
    }

    func getAbsoluteIndex(for bookID: UUID, selectedText: String) async -> Int? {
        let probe = Self.matchingProbe(from: selectedText)
        guard !probe.isEmpty else {
            AppLogger.log(tag: "NarrativeContextStore", "❌ probe is empty, selectedText was: \(selectedText.prefix(100))")
            return nil
        }

        let escapedRaw = selectedText.prefix(120).replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\r", with: "⏎")
        AppLogger.log(tag: "NarrativeContextStore", "📝 raw (\\n→⏎): \"\(escapedRaw)\"")
        AppLogger.log(tag: "NarrativeContextStore", "🔍 probe: \"\(probe.prefix(120))\"")

        do {
            return try await dbQueue.read { db in
                if AppLogger.isEnabled {
                    let totalCount = try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM paragraphs WHERE bookID = ?",
                        arguments: [bookID]
                    ) ?? 0
                    AppLogger.log(tag: "NarrativeContextStore", "📦 paragraphs in DB for book: \(totalCount)")

                    if totalCount > 0 {
                        let sample = try Row.fetchAll(
                            db,
                            sql: "SELECT absoluteIndex, text FROM paragraphs WHERE bookID = ? ORDER BY absoluteIndex ASC LIMIT 3",
                            arguments: [bookID]
                        )
                        for row in sample {
                            let idx: Int = row["absoluteIndex"]
                            let txt: String = row["text"]
                            AppLogger.log(tag: "NarrativeContextStore", "  sample[\(idx)]: \"\(txt.prefix(80))\"")
                        }
                    }
                }

                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT absoluteIndex
                        FROM paragraphs
                        WHERE bookID = ? AND text LIKE ?
                        ORDER BY absoluteIndex ASC
                        LIMIT 1
                        """,
                    arguments: [bookID, "%\(probe)%"]
                )

                if let result: Int = row?["absoluteIndex"] {
                    AppLogger.log(tag: "NarrativeContextStore", "✅ matched absoluteIndex: \(result)")
                    return result
                } else {
                    AppLogger.log(tag: "NarrativeContextStore", "❌ no match found for probe")
                    return nil
                }
            }
        } catch {
            AppLogger.log(tag: "NarrativeContextStore", "❌ DB error: \(error)")
            return nil
        }
    }

    // MARK: - Text normalization

    /// Normalizes Readium-rendered text to match SwiftSoup .text() output.
    ///
    /// SwiftSoup strips tags, decodes HTML entities, and collapses whitespace.
    /// Readium's text.highlight is already entity-decoded by the browser, but
    /// can contain soft hyphens (U+00AD) from hyphenation and non-breaking
    /// spaces (U+00A0) from CSS layout. This function bridges that gap.
    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the substring of a (possibly multi-paragraph) selection that
    /// best identifies the paragraph the reader is currently at.
    ///
    /// Readium separates DOM paragraphs with \n in text.highlight. We split on
    /// \n before normalizing so the boundary isn't collapsed into a space.
    /// The last non-empty line belongs to the second (current) paragraph.
    /// For single-paragraph selections there is no \n, so we fall through to
    /// sentence-boundary splitting on the full normalized text.
    private static func matchingProbe(from text: String) -> String {
        let lines = text
            .components(separatedBy: "\n")
            .map { normalize($0) }
            .filter { $0.count > 10 }

        if lines.count > 1, let lastLine = lines.last {
            return lastLine
        }

        let normalized = normalize(text)
        guard !normalized.isEmpty else { return "" }

        let fragments = normalized.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        if let last = fragments.last(where: { $0.trimmingCharacters(in: .whitespaces).count > 20 }) {
            return last.trimmingCharacters(in: .whitespaces)
        }

        return String(normalized.suffix(60)).trimmingCharacters(in: .whitespaces)
    }
}
