import Foundation
import GRDB

final class DatabaseManager {
    static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    let dbQueue: DatabaseQueue

    private init() throws {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dbURL = appSupport.appendingPathComponent("readora.sqlite")

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        try Self.makeMigrator().migrate(dbQueue)
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_narrative_graph_schema") { db in
            try db.create(table: "books") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("format", .text).notNull()
                t.column("localFilename", .text)
                t.column("importDate", .datetime).notNull()
                t.column("preprocessingStatus", .text).notNull()
                t.column("aiAnalysisProgress", .double).notNull().defaults(to: 0.0)
            }

            try db.create(table: "chapters") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references(
                    "books", onDelete: .cascade)
                t.column("indexInBook", .integer).notNull()
                t.column("title", .text)
                t.column("startParagraphID", .integer)
                t.column("endParagraphID", .integer)
            }

            try db.create(table: "paragraphs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bookID", .text).notNull().indexed().references(
                    "books", onDelete: .cascade)
                t.column("chapterID", .text).indexed().references("chapters", onDelete: .setNull)
                t.column("indexInChapter", .integer).notNull()
                t.column("absoluteIndex", .integer).notNull()
                t.column("text", .text).notNull()
                t.uniqueKey(["bookID", "absoluteIndex"])
            }

            try db.create(table: "entities") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references(
                    "books", onDelete: .cascade)
                t.column("canonicalName", .text).notNull()
                t.column("type", .text).notNull()
                t.column("aliasesJSON", .text).notNull()
                t.column("description", .text)
                t.column("importanceScore", .double).notNull().defaults(to: 0.0)
                t.column("firstMentionParagraphID", .integer)
                t.column("lastMentionParagraphID", .integer)
            }

            try db.create(table: "entityMentions") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("entityID", .text).notNull().indexed().references(
                    "entities", onDelete: .cascade)
                t.column("paragraphID", .integer).notNull().indexed().references(
                    "paragraphs", onDelete: .cascade)
                t.column("surfaceForm", .text).notNull()
                t.column("charStart", .integer).notNull()
                t.column("charEnd", .integer).notNull()
                t.column("confidence", .double).notNull()
            }

            try db.create(table: "scenes") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references(
                    "books", onDelete: .cascade)
                t.column("indexInBook", .integer).notNull()
                t.column("firstParagraphID", .integer).notNull().indexed().references(
                    "paragraphs", onDelete: .cascade)
                t.column("lastParagraphID", .integer).notNull().indexed().references(
                    "paragraphs", onDelete: .cascade)
                t.column("summary", .text).notNull()
                t.column("locationText", .text)
                t.column("importanceScore", .double).notNull().defaults(to: 0.0)
            }

            try db.create(
                index: "sceneParagraphRange", on: "scenes",
                columns: ["firstParagraphID", "lastParagraphID"])

            try db.create(table: "events") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references(
                    "books", onDelete: .cascade)
                t.column("indexInNarrative", .integer).notNull()
                t.column("summary", .text).notNull()
                t.column("firstParagraphID", .integer).notNull().indexed().references(
                    "paragraphs", onDelete: .cascade)
                t.column("lastParagraphID", .integer).notNull().indexed().references(
                    "paragraphs", onDelete: .cascade)
                t.column("importanceScore", .double).notNull().defaults(to: 0.0)
            }

            try db.create(
                index: "eventParagraphRange", on: "events",
                columns: ["firstParagraphID", "lastParagraphID"])

            try db.create(table: "aiConversations") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references(
                    "books", onDelete: .cascade)
                t.column("paragraphID", .integer).notNull().indexed().references(
                    "paragraphs", onDelete: .cascade)
                t.column("passageText", .text).notNull()
                t.column("locatorJSON", .text)
                t.column("chapterTitle", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "aiMessages") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("conversationID", .text).notNull().indexed().references(
                    "aiConversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        return migrator
    }

    func runStartupSmokeTest() throws {
        try dbQueue.read { db in
            _ = try Int.fetchOne(db, sql: "SELECT 1")
        }
    }
}