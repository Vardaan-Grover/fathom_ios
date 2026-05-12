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

    func getAbsoluteIndex(for bookID: UUID, selectedText: String, locatorJSON: String?) async -> Int? {
        let probe = Self.matchingProbe(from: selectedText)
        guard !probe.isEmpty else {
            AppLogger.log(tag: "NarrativeContextStore", "❌ probe is empty")
            return nil
        }

        AppLogger.log(tag: "NarrativeContextStore", "🔍 probe: \"\(probe.prefix(120))\"")
        if AppLogger.isEnabled {
            let probeHex = probe.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
            AppLogger.log(tag: "NarrativeContextStore", "🔍 probe hex: \(probeHex)")
        }

        guard let hint = locatorJSON.flatMap({ Self.parseLocatorHint(from: $0) }),
              let href = hint.href else {
            AppLogger.log(tag: "NarrativeContextStore", "❌ no locator href, cannot resolve absoluteIndex")
            return nil
        }

        let result = await chapterRestrictedSearch(
            bookID: bookID, href: href, probe: probe, progression: hint.progression)
        AppLogger.log(
            tag: "NarrativeContextStore",
            result != nil ? "✅ chapter match: \(result!)" : "❌ no match in chapter")
        return result
    }

    // MARK: - Locator parsing

    private struct LocatorHint {
        let href: String?
        let progression: Double?
    }

    private static func parseLocatorHint(from json: String) -> LocatorHint? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let href = obj["href"] as? String
        let locations = obj["locations"] as? [String: Any]
        return LocatorHint(
            href: href,
            progression: locations?["progression"] as? Double
        )
    }

    private static func normalizeHref(_ href: String) -> String {
        href.hasPrefix("/") ? String(href.dropFirst()) : href
    }

    // MARK: - Chapter-restricted search

    private func chapterRestrictedSearch(
        bookID: UUID, href: String, probe: String, progression: Double?
    ) async -> Int? {
        let normalizedHref = Self.normalizeHref(href)
        do {
            return try await dbQueue.read { db in
                // Log a sample of stored hrefs to compare against the locator's href
                if AppLogger.isEnabled {
                    let storedHrefs = try Row.fetchAll(
                        db,
                        sql: "SELECT href FROM chapters WHERE bookID = ? LIMIT 3",
                        arguments: [bookID]
                    ).map { ($0["href"] as String?) ?? "NULL" }
                    AppLogger.log(tag: "NarrativeContextStore", "🔎 looking for href: \"\(normalizedHref)\"")
                    AppLogger.log(tag: "NarrativeContextStore", "🗂 stored hrefs sample: \(storedHrefs)")
                }

                guard let chapterRow = try Row.fetchOne(
                    db,
                    sql: "SELECT id FROM chapters WHERE bookID = ? AND href = ?",
                    arguments: [bookID, normalizedHref]
                ) else {
                    AppLogger.log(tag: "NarrativeContextStore", "❌ no chapter found for href: \(normalizedHref)")
                    return nil
                }

                let chapterID: UUID = chapterRow["id"]

                if AppLogger.isEnabled {
                    let globalCount = try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM paragraphs WHERE bookID = ? AND text LIKE ?",
                        arguments: [bookID, "%\(probe)%"]
                    ) ?? 0
                    AppLogger.log(tag: "NarrativeContextStore", "🧪 global LIKE count: \(globalCount)")

                    let chapterOnlyCount = try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM paragraphs WHERE chapterID = ? AND text LIKE ?",
                        arguments: [chapterID, "%\(probe)%"]
                    ) ?? 0
                    AppLogger.log(tag: "NarrativeContextStore", "🧪 chapter LIKE count: \(chapterOnlyCount)")

                    let testRows = try Row.fetchAll(
                        db,
                        sql: "SELECT absoluteIndex FROM paragraphs WHERE chapterID = ? AND text LIKE ?",
                        arguments: [chapterID, "%\(probe)%"]
                    )
                    AppLogger.log(tag: "NarrativeContextStore", "🧪 test fetchAll count: \(testRows.count)")
                    if let first = testRows.first {
                        AppLogger.log(tag: "NarrativeContextStore", "🧪 test first absoluteIndex: \(first["absoluteIndex"] as Int? ?? -1)")
                    }
                }

                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT absoluteIndex, indexInChapter FROM paragraphs WHERE chapterID = ? AND text LIKE ? ORDER BY absoluteIndex ASC",
                    arguments: [chapterID, "%\(probe)%"]
                )
                AppLogger.log(tag: "NarrativeContextStore", "🧪 main rows.count: \(rows.count)")

                if AppLogger.isEnabled {
                    let totalInChapter = try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM paragraphs WHERE chapterID = ?",
                        arguments: [chapterID]
                    ) ?? 0
                    AppLogger.log(tag: "NarrativeContextStore", "📖 paragraphs in chapter: \(totalInChapter)")
                    let sampleRows = try Row.fetchAll(
                        db,
                        sql: "SELECT text FROM paragraphs WHERE chapterID = ? LIMIT 3",
                        arguments: [chapterID]
                    )
                    for (i, r) in sampleRows.enumerated() {
                        let t = (r["text"] as String?) ?? ""
                        AppLogger.log(tag: "NarrativeContextStore", "  para[\(i)]: \"\(t.prefix(80))\"")
                        let hex = t.unicodeScalars.prefix(40).map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                        AppLogger.log(tag: "NarrativeContextStore", "  para[\(i)] hex: \(hex)")
                    }
                }
                guard !rows.isEmpty else { return nil }
                if rows.count == 1 { return rows[0]["absoluteIndex"] as Int? }

                if let progression {
                    let totalInChapter = try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM paragraphs WHERE chapterID = ?",
                        arguments: [chapterID]
                    ) ?? 1
                    let estimatedIndex = Int(progression * Double(totalInChapter))
                    return rows.min(by: {
                        abs(($0["indexInChapter"] as Int? ?? 0) - estimatedIndex) <
                        abs(($1["indexInChapter"] as Int? ?? 0) - estimatedIndex)
                    })?["absoluteIndex"] as Int?
                }

                return rows[0]["absoluteIndex"] as Int?
            }
        } catch { return nil }
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

        if lines.count > 1, let firstLine = lines.first {
            return firstLine
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
