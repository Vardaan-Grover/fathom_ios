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

    // Internal (not private) so FathomTests can run the full migration chain
    // against an in-memory database.
    static func makeMigrator() -> DatabaseMigrator {
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

        migrator.registerMigration("v12_add_notes") { db in
            // highlightColor added in v13; keep this migration unchanged so
            // existing installs that already ran v12 don't lose data.
            try db.create(table: "notes") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("locatorJSON", .text).notNull()
                t.column("selectedText", .text).notNull()
                t.column("noteContent", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("chapterTitle", .text)
                t.column("pageNumber", .integer)
            }
        }

        migrator.registerMigration("v13_add_note_highlight_color") { db in
            try db.alter(table: "notes") { t in
                t.add(column: "highlightColor", .text).notNull().defaults(to: "indigo")
            }
        }

        migrator.registerMigration("v14_create_highlights") { db in
            try db.create(table: "highlights") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("locatorJSON", .text).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("color", .text).notNull().defaults(to: "yellow")
            }
        }

        migrator.registerMigration("v15_create_bookmarks") { db in
            try db.create(table: "bookmarks") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("locatorJSON", .text).notNull()
                t.column("progression", .double).notNull()
                t.column("chapterTitle", .text)
                t.column("pageNumber", .integer)
                t.column("createdAt", .datetime).notNull().indexed()
            }
        }

        migrator.registerMigration("v16_add_book_title_to_saved_words") { db in
            try db.alter(table: "saved_words") { t in
                t.add(column: "bookTitle", .text)
            }
        }

        migrator.registerMigration("v17_add_sort_orders") { db in
            // Guard against the column already existing (e.g. from a partial prior run)
            let catColumns = try db.columns(in: "bookCategories").map(\.name)
            if !catColumns.contains("sortOrder") {
                try db.alter(table: "bookCategories") { t in
                    t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
                }
                // Rank each shelf by createdAt ascending — pure SQL, no UUID decoding
                try db.execute(sql: """
                    UPDATE bookCategories
                    SET sortOrder = (
                        SELECT COUNT(*)
                        FROM bookCategories b2
                        WHERE b2.createdAt < bookCategories.createdAt
                    )
                    """)
            }

            let memColumns = try db.columns(in: "bookCategoryMemberships").map(\.name)
            if !memColumns.contains("sortOrder") {
                try db.alter(table: "bookCategoryMemberships") { t in
                    t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
                }
                // Rank each membership within its category by addedAt descending — pure SQL
                try db.execute(sql: """
                    UPDATE bookCategoryMemberships
                    SET sortOrder = (
                        SELECT COUNT(*)
                        FROM bookCategoryMemberships m2
                        WHERE m2.categoryID = bookCategoryMemberships.categoryID
                          AND m2.addedAt > bookCategoryMemberships.addedAt
                    )
                    """)
            }
        }

        migrator.registerMigration("v18_add_pinned_at_to_saved_words") { db in
            try db.alter(table: "saved_words") { t in
                t.add(column: "pinnedAt", .datetime)
            }
        }

        migrator.registerMigration("v22_add_book_completion") { db in
            try db.alter(table: "books") { t in
                t.add(column: "rating", .integer)
                t.add(column: "reflection", .text)
                t.add(column: "finishedAt", .datetime)
            }
        }

        migrator.registerMigration("v23_add_reflection_image") { db in
            try db.alter(table: "books") { t in
                t.add(column: "reflectionImageFilename", .text)
            }
        }

        migrator.registerMigration("v24_add_reading_activity") { db in
            try db.create(table: "readingActivity") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("bookID", .text).notNull().indexed().references("books", onDelete: .cascade)
                t.column("date", .text).notNull().indexed()
                t.column("duration", .double).notNull().defaults(to: 0.0)
                t.column("createdAt", .datetime).notNull()
            }
            // Unique constraint on bookID and date so we upsert rather than duplicate
            try db.create(index: "idx_readingActivity_book_date", on: "readingActivity", columns: ["bookID", "date"], unique: true)
        }

        migrator.registerMigration("v25_add_readingActivity_modifiedAt") { db in
            try db.alter(table: "readingActivity") { t in
                t.add(column: "modifiedAt", .datetime).notNull().defaults(to: Date())
            }
        }

        // ── Sync infrastructure ────────────────────────────────────────────

        // v19 — soft-delete tombstone column on annotation tables.
        // Deletions set deletedAt instead of removing the row so tombstones
        // propagate to other devices via CloudKit.
        migrator.registerMigration("v19_add_deleted_at") { db in
            for table in ["highlights", "notes", "bookmarks", "saved_words"] {
                try db.alter(table: table) { t in
                    t.add(column: "deletedAt", .datetime)
                }
            }
        }

        // v20 — modifiedAt timestamp on every synced table.
        // Backfilled from each table's existing creation-time column.
        // AFTER UPDATE triggers keep modifiedAt current without touching Swift models.
        migrator.registerMigration("v20_add_modified_at") { db in
            // (tableName, column to backfill from)
            let tables: [(String, String)] = [
                ("books",                    "importDate"),
                ("bookCategories",           "createdAt"),
                ("bookCategoryMemberships",  "addedAt"),
                ("highlights",               "createdAt"),
                ("notes",                    "createdAt"),
                ("bookmarks",                "createdAt"),
                ("saved_words",              "createdAt"),
                ("aiConversations",          "createdAt"),
            ]
            for (table, sourceCol) in tables {
                try db.alter(table: table) { t in
                    t.add(column: "modifiedAt", .datetime)
                }
                try db.execute(sql: "UPDATE \(table) SET modifiedAt = \(sourceCol) WHERE modifiedAt IS NULL")
            }

            // AFTER UPDATE triggers auto-stamp modifiedAt.
            // SQLite's recursive_triggers is OFF by default so the UPDATE inside
            // the trigger body does NOT re-fire the trigger — no infinite loop.
            let idTables = ["books", "bookCategories", "highlights", "notes",
                            "bookmarks", "saved_words", "aiConversations", "readingActivity"]
            for table in idTables {
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS \(table)_stamp_modifiedAt
                    AFTER UPDATE ON \(table)
                    FOR EACH ROW
                    BEGIN
                        UPDATE \(table)
                        SET    modifiedAt = strftime('%Y-%m-%dT%H:%M:%f', 'now')
                        WHERE  id = NEW.id;
                    END
                    """)
            }
            // bookCategoryMemberships uses a composite primary key (no id column).
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS bookCategoryMemberships_stamp_modifiedAt
                AFTER UPDATE ON bookCategoryMemberships
                FOR EACH ROW
                BEGIN
                    UPDATE bookCategoryMemberships
                    SET    modifiedAt = strftime('%Y-%m-%dT%H:%M:%f', 'now')
                    WHERE  bookID = NEW.bookID AND categoryID = NEW.categoryID;
                END
                """)
        }

        // v21 — CloudKit change-data-capture queue + triggers.
        // Every insert / update / delete on a synced table automatically adds a
        // row here.  The SyncEngine observes this table (GRDB ValueObservation)
        // and flushes pending entries to CloudKit.
        //
        // PRIMARY KEY (recordType, recordID) deduplicates: rapid changes to the
        // same record collapse into one pending entry.
        migrator.registerMigration("v21_cloudkit_sync_queue") { db in
            try db.create(table: "cloudkit_pending_changes") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID",   .text).notNull()
                // 'upsert' — insert or update the CKRecord
                // 'delete' — delete the CKRecord (hard-deleted rows)
                t.column("operation",  .text).notNull().defaults(to: "upsert")
                t.column("queuedAt",   .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.primaryKey(["recordType", "recordID"])
            }

            // ── Upsert-only tables (soft-deletes, never hard-deleted) ──────
            for table in ["highlights", "notes", "bookmarks", "saved_words", "readingActivity"] {
                let type = Self.cloudKitType(for: table)
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS \(table)_ck_insert
                    AFTER INSERT ON \(table)
                    BEGIN
                        INSERT OR REPLACE INTO cloudkit_pending_changes
                            (recordType, recordID, operation, queuedAt)
                        VALUES ('\(type)', NEW.id, 'upsert', CURRENT_TIMESTAMP);
                    END
                    """)
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS \(table)_ck_update
                    AFTER UPDATE ON \(table)
                    BEGIN
                        INSERT OR REPLACE INTO cloudkit_pending_changes
                            (recordType, recordID, operation, queuedAt)
                        VALUES ('\(type)', NEW.id, 'upsert', CURRENT_TIMESTAMP);
                    END
                    """)
            }

            // ── Hard-delete tables (insert/update → upsert, delete → delete) ─
            for table in ["books", "bookCategories", "aiConversations"] {
                let type = Self.cloudKitType(for: table)
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS \(table)_ck_insert
                    AFTER INSERT ON \(table)
                    BEGIN
                        INSERT OR REPLACE INTO cloudkit_pending_changes
                            (recordType, recordID, operation, queuedAt)
                        VALUES ('\(type)', NEW.id, 'upsert', CURRENT_TIMESTAMP);
                    END
                    """)
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS \(table)_ck_update
                    AFTER UPDATE ON \(table)
                    BEGIN
                        INSERT OR REPLACE INTO cloudkit_pending_changes
                            (recordType, recordID, operation, queuedAt)
                        VALUES ('\(type)', NEW.id, 'upsert', CURRENT_TIMESTAMP);
                    END
                    """)
                try db.execute(sql: """
                    CREATE TRIGGER IF NOT EXISTS \(table)_ck_delete
                    AFTER DELETE ON \(table)
                    BEGIN
                        INSERT OR REPLACE INTO cloudkit_pending_changes
                            (recordType, recordID, operation, queuedAt)
                        VALUES ('\(type)', OLD.id, 'delete', CURRENT_TIMESTAMP);
                    END
                    """)
            }

            // bookCategoryMemberships — composite key, serialised as "bookID|categoryID"
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS bookCategoryMemberships_ck_insert
                AFTER INSERT ON bookCategoryMemberships
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('BookCategoryMembership',
                            NEW.bookID || '|' || NEW.categoryID,
                            'upsert', CURRENT_TIMESTAMP);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS bookCategoryMemberships_ck_delete
                AFTER DELETE ON bookCategoryMemberships
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('BookCategoryMembership',
                            OLD.bookID || '|' || OLD.categoryID,
                            'delete', CURRENT_TIMESTAMP);
                END
                """)

            // aiMessages — inserting a message queues the parent conversation
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS aiMessages_ck_insert
                AFTER INSERT ON aiMessages
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('AIConversation', NEW.conversationID, 'upsert', CURRENT_TIMESTAMP);
                END
                """)

            // Seed queue with every existing record so first-run push is handled
            // automatically by the normal push path rather than special-case code.
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'Book', id, 'upsert' FROM books
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'BookCategory', id, 'upsert' FROM bookCategories
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'BookCategoryMembership', bookID || '|' || categoryID, 'upsert'
                FROM bookCategoryMemberships
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'Highlight', id, 'upsert' FROM highlights
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'Note', id, 'upsert' FROM notes
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'Bookmark', id, 'upsert' FROM bookmarks
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'SavedWord', id, 'upsert' FROM saved_words
                """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes (recordType, recordID, operation)
                SELECT 'ReadingActivity', id, 'upsert' FROM readingActivity
                """)
        }

        // v26 — AI Companion is dormant (kept in codebase, not user-facing).
        // Live chats are stored in ai_threads.json (AIThreadStore), so the
        // aiConversations CDC triggers only queued rows that could never be
        // pushed with real data. Drop the triggers and purge queued entries.
        // Recreate the triggers in a future migration if the feature ships.
        migrator.registerMigration("v26_disable_ai_conversation_sync") { db in
            for trigger in [
                "aiConversations_ck_insert",
                "aiConversations_ck_update",
                "aiConversations_ck_delete",
                "aiMessages_ck_insert",
            ] {
                try db.execute(sql: "DROP TRIGGER IF EXISTS \(trigger)")
            }
            try db.execute(
                sql: "DELETE FROM cloudkit_pending_changes WHERE recordType = 'AIConversation'")
        }

        // v27 — millisecond-precision CDC queue timestamps.
        // The v21 triggers stamp queuedAt with CURRENT_TIMESTAMP (second
        // precision). The SyncEngine clears processed queue rows by exact
        // (recordType, recordID, queuedAt) match so that a row re-queued
        // *during* a push (INSERT OR REPLACE writes a fresh queuedAt) survives
        // the cleanup and is pushed again. Second precision makes same-second
        // collisions realistic; recreate the triggers with millisecond stamps.
        // (aiConversations/aiMessages triggers were dropped in v26.)
        migrator.registerMigration("v27_millisecond_queue_timestamps") { db in
            let stamp = "strftime('%Y-%m-%dT%H:%M:%f', 'now')"

            // Upsert-only tables (soft-deletes, never hard-deleted).
            for table in ["highlights", "notes", "bookmarks", "saved_words", "readingActivity"] {
                let type = Self.cloudKitType(for: table)
                for (suffix, event) in [("_ck_insert", "INSERT"), ("_ck_update", "UPDATE")] {
                    try db.execute(sql: "DROP TRIGGER IF EXISTS \(table)\(suffix)")
                    try db.execute(sql: """
                        CREATE TRIGGER \(table)\(suffix)
                        AFTER \(event) ON \(table)
                        BEGIN
                            INSERT OR REPLACE INTO cloudkit_pending_changes
                                (recordType, recordID, operation, queuedAt)
                            VALUES ('\(type)', NEW.id, 'upsert', \(stamp));
                        END
                        """)
                }
            }

            // Hard-delete tables.
            for table in ["books", "bookCategories"] {
                let type = Self.cloudKitType(for: table)
                for (suffix, event) in [("_ck_insert", "INSERT"), ("_ck_update", "UPDATE")] {
                    try db.execute(sql: "DROP TRIGGER IF EXISTS \(table)\(suffix)")
                    try db.execute(sql: """
                        CREATE TRIGGER \(table)\(suffix)
                        AFTER \(event) ON \(table)
                        BEGIN
                            INSERT OR REPLACE INTO cloudkit_pending_changes
                                (recordType, recordID, operation, queuedAt)
                            VALUES ('\(type)', NEW.id, 'upsert', \(stamp));
                        END
                        """)
                }
                try db.execute(sql: "DROP TRIGGER IF EXISTS \(table)_ck_delete")
                try db.execute(sql: """
                    CREATE TRIGGER \(table)_ck_delete
                    AFTER DELETE ON \(table)
                    BEGIN
                        INSERT OR REPLACE INTO cloudkit_pending_changes
                            (recordType, recordID, operation, queuedAt)
                        VALUES ('\(type)', OLD.id, 'delete', \(stamp));
                    END
                    """)
            }

            // bookCategoryMemberships — composite key "bookID|categoryID".
            try db.execute(sql: "DROP TRIGGER IF EXISTS bookCategoryMemberships_ck_insert")
            try db.execute(sql: """
                CREATE TRIGGER bookCategoryMemberships_ck_insert
                AFTER INSERT ON bookCategoryMemberships
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('BookCategoryMembership',
                            NEW.bookID || '|' || NEW.categoryID,
                            'upsert', \(stamp));
                END
                """)
            try db.execute(sql: "DROP TRIGGER IF EXISTS bookCategoryMemberships_ck_delete")
            try db.execute(sql: """
                CREATE TRIGGER bookCategoryMemberships_ck_delete
                AFTER DELETE ON bookCategoryMemberships
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('BookCategoryMembership',
                            OLD.bookID || '|' || OLD.categoryID,
                            'delete', \(stamp));
                END
                """)
        }

        return migrator
    }

    // Maps a SQLite table name to its CloudKit record type string.
    // Kept here (alongside the migration that creates the triggers) so the
    // strings stay in sync automatically.
    static func cloudKitType(for tableName: String) -> String {
        switch tableName {
        case "books":                   return "Book"
        case "bookCategories":          return "BookCategory"
        case "bookCategoryMemberships": return "BookCategoryMembership"
        case "highlights":              return "Highlight"
        case "notes":                   return "Note"
        case "bookmarks":               return "Bookmark"
        case "saved_words":             return "SavedWord"
        case "aiConversations":         return "AIConversation"
        case "readingActivity":         return "ReadingActivity"
        default:                        return tableName
        }
    }

    func runStartupSmokeTest() throws {
        try dbQueue.read { db in
            _ = try Int.fetchOne(db, sql: "SELECT 1")
        }
    }
}
