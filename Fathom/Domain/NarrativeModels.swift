import Foundation
import GRDB

enum PreprocessingStatus: String, Codable {
    case pending
    case inProgress
    case completed
    case failed
}

struct NarrativeChapter: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName: String = "chapters"

    var id: UUID
    var bookID: UUID
    var indexInBook: Int
    var href: String?
    var title: String?
    var startParagraphID: Int64?
    var endParagraphID: Int64?
}

struct NarrativeParagraph: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName: String = "paragraphs"

    var id: Int64?
    var bookID: UUID
    var chapterID: UUID?
    var indexInChapter: Int
    var absoluteIndex: Int
    var text: String
}

struct NarrativeEntity: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName: String = "entities"

    var id: UUID
    var bookID: UUID
    var canonicalName: String
    var type: String
    var aliasesJSON: String
    var description: String?
    var importanceScore: Double
    var firstMentionParagraphID: Int64?
    var lastMentionParagraphID: Int64?
}

struct NarrativeEntityMention: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName: String = "entityMentions"

    var id: UUID
    var entityID: UUID
    var paragraphID: Int64
    var surfaceForm: String
    var charStart: Int
    var charEnd: Int
    var confidence: Double
}

struct NarrativeScene: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName: String = "scenes"

    var id: UUID
    var bookID: UUID
    var indexInBook: Int

    var firstParagraphID: Int64
    var lastParagraphID: Int64

    var summary: String
    var locationText: String?

    var importanceScore: Double
}

struct NarrativeEvent: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName: String = "events"

    var id: UUID
    var bookID: UUID
    var indexInNarrative: Int

    var summary: String

    var firstParagraphID: Int64
    var lastParagraphID: Int64

    var importanceScore: Double
}
