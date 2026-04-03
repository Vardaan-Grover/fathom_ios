import Foundation
import GRDB

struct NarrativePromptContext {
    let currentParagraphID: Int64?
    let currentParagraphText: String?
    let events: [NarrativePromptEvent]
    let entities: [NarrativePromptEntity]

    var promptContext: String {
        var sections: [String] = []

        if let currentParagraphText, !currentParagraphText.isEmpty {
            let excerpt = String(currentParagraphText.prefix(450))
            sections.append("[CURRENT_PARAGRAPH]\n\(excerpt)")
        }

        if !events.isEmpty {
            let eventLines = events.map { "- \($0.summary)" }.joined(separator: "\n")
            sections.append("[RELEVANT_PAST_EVENTS]\n\(eventLines)")
        }

        if !entities.isEmpty {
            let entityLines = entities.map { entity in
                if entity.aliases.isEmpty {
                    return "- \(entity.name) (\(entity.type))"
                }
                let aliasList = entity.aliases.joined(separator: ", ")
                return "- \(entity.name) (\(entity.type)); aliases: \(aliasList)"
            }.joined(separator: "\n")
            sections.append("[RELEVANT_ENTITIES]\n\(entityLines)")
        }

        return sections.joined(separator: "\n\n")
    }
}

struct NarrativePromptEvent {
    let summary: String
    let firstParagraphID: Int64
    let lastParagraphID: Int64
    let importanceScore: Double
}

struct NarrativePromptEntity {
    let name: String
    let type: String
    let aliases: [String]
    let importanceScore: Double
}

actor NarrativeContextStore {
    static let shared = NarrativeContextStore(dbQueue: DatabaseManager.shared.dbQueue)

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func buildPromptContext(
        bookID: UUID,
        selectedText: String,
        maxEvents: Int = 8,
        maxEntities: Int = 8
    ) async -> NarrativePromptContext {
        do {
            return try await dbQueue.read { db in
                let paragraph = try resolveParagraph(
                    db: db,
                    bookID: bookID,
                    selectedText: selectedText
                )

                guard let paragraphID = paragraph?.id else {
                    return NarrativePromptContext(
                        currentParagraphID: nil,
                        currentParagraphText: nil,
                        events: [],
                        entities: []
                    )
                }

                let events = try fetchEvents(
                    db: db,
                    bookID: bookID,
                    currentParagraphID: paragraphID,
                    limit: maxEvents
                )

                let entities = try fetchEntities(
                    db: db,
                    bookID: bookID,
                    currentParagraphID: paragraphID,
                    limit: maxEntities
                )

                return NarrativePromptContext(
                    currentParagraphID: paragraphID,
                    currentParagraphText: paragraph?.text,
                    events: events,
                    entities: entities
                )
            }
        } catch {
            return NarrativePromptContext(
                currentParagraphID: nil,
                currentParagraphText: nil,
                events: [],
                entities: []
            )
        }
    }

    private func resolveParagraph(
        db: Database,
        bookID: UUID,
        selectedText: String
    ) throws -> (id: Int64, text: String)? {
        let normalized = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let pattern = "%\(normalized)%"

        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, text
                FROM paragraphs
                WHERE bookID = ? AND text LIKE ?
                ORDER BY absoluteIndex ASC
                LIMIT 1
                """,
            arguments: [bookID, pattern]
        )

        guard let row else { return nil }
        return (id: row["id"], text: row["text"])
    }

    private func fetchEvents(
        db: Database,
        bookID: UUID,
        currentParagraphID: Int64,
        limit: Int
    ) throws -> [NarrativePromptEvent] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT summary, firstParagraphID, lastParagraphID, importanceScore
                FROM events
                WHERE bookID = ?
                  AND lastParagraphID <= ?
                ORDER BY importanceScore DESC, lastParagraphID DESC
                LIMIT ?
                """,
            arguments: [bookID, currentParagraphID, limit]
        )

        return rows.map { row in
            NarrativePromptEvent(
                summary: row["summary"],
                firstParagraphID: row["firstParagraphID"],
                lastParagraphID: row["lastParagraphID"],
                importanceScore: row["importanceScore"]
            )
        }
    }

    private func fetchEntities(
        db: Database,
        bookID: UUID,
        currentParagraphID: Int64,
        limit: Int
    ) throws -> [NarrativePromptEntity] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT canonicalName, type, aliasesJSON, importanceScore
                FROM entities
                WHERE bookID = ?
                  AND COALESCE(firstMentionParagraphID, 0) <= ?
                ORDER BY importanceScore DESC, COALESCE(lastMentionParagraphID, 0) DESC
                LIMIT ?
                """,
            arguments: [bookID, currentParagraphID, limit]
        )

        return rows.map { row in
            let aliasesJSON: String = row["aliasesJSON"]
            let aliasesData = aliasesJSON.data(using: .utf8)
            let aliases = (aliasesData.flatMap { try? JSONDecoder().decode([String].self, from: $0) }) ?? []

            return NarrativePromptEntity(
                name: row["canonicalName"],
                type: row["type"],
                aliases: aliases,
                importanceScore: row["importanceScore"]
            )
        }
    }
}
