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

        let dbURL = appSupport.appendingPathComponent("fathom.sqlite")
        AppLogger.log(tag: "Database", "SQLite located at: \(dbURL.path)")

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

        migrator.registerMigration("v2_add_book_metadata") { db in
            try db.alter(table: "books") { t in
                t.add(column: "description", .text)
                t.add(column: "language", .text)
                t.add(column: "publisher", .text)
                t.add(column: "coverFilename", .text)
            }
        }

        migrator.registerMigration("v3_add_reading_estimates") { db in
            try db.alter(table: "books") { t in
                t.add(column: "estimatedPageCount", .integer)
                t.add(column: "estimatedReadingTimeMinutes", .integer)
            }
        }

        migrator.registerMigration("v4_add_book_categories") { db in
            try db.create(table: "bookCategories") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("name", .text).notNull()
                t.column("shelfColorHex", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v5_add_book_category_memberships") { db in
            try db.create(table: "bookCategoryMemberships") { t in
                t.column("bookID", .text).notNull().references("books", onDelete: .cascade)
                t.column("categoryID", .text).notNull().references(
                    "bookCategories", onDelete: .cascade)
                t.column("addedAt", .datetime).notNull()
                t.primaryKey(["bookID", "categoryID"])
            }
        }

        migrator.registerMigration("v6_add_ai_enabled") { db in
            try db.alter(table: "books") { t in
                t.add(column: "aiEnabled", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v7_add_backend_book_id") { db in
            try db.alter(table: "books") { t in
                t.add(column: "backendBookID", .text)
            }
            // Existing AI-enabled books used book.id as the backend ID (old behavior).
            try db.execute(sql: "UPDATE books SET backendBookID = id WHERE aiEnabled = 1")
        }

        migrator.registerMigration("v8_add_content_hash") { db in
            try db.alter(table: "books") { t in
                t.add(column: "contentHash", .text)
            }
        }

        migrator.registerMigration("v9_create_vocabulary_schema") { db in
            try db.create(table: "saved_words") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("word", .text).notNull().indexed()
                t.column("language", .text).notNull().indexed()
                t.column("partsOfSpeech", .text).notNull()  // Comma-separated parts of speech

                // Book association
                t.column("bookID", .text).indexed().references("books", onDelete: .setNull)
                t.column("chapter", .text)
                t.column("pageNumber", .integer)
                t.column("locatorJSON", .text)

                t.column("contextSentence", .text)
                t.column("fullDictionaryJSON", .blob)  // storing raw JSON payload as blob
                t.column("createdAt", .datetime).notNull().indexed()
            }
        }

        migrator.registerMigration("v10_add_chapter_href") { db in
            try db.alter(table: "chapters") { t in
                t.add(column: "href", .text)
            }
        }

        migrator.registerMigration("v11_add_last_read_at") { db in
            try db.alter(table: "books") { t in
                t.add(column: "lastReadAt", .datetime)
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
