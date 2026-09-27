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

        // The apply context only ever changes inside a transaction, so a crash
        // rolls it back — but a context left raised would silently stop every
        // local change from syncing, so it is cleared at launch regardless.
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE sync_apply_context SET active = 0")
        }
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

        // v28 — full-text index over the library, backing the search field on
        // the home and classic screens.
        //
        // `content='books'` makes this an external-content index: FTS5 stores
        // only the inverted index and reads column values back from `books`,
        // so the text is not duplicated on disk.
        //
        // `prefix='2 3'` pre-builds 2- and 3-character prefix indexes. Search
        // runs on every keystroke, and the first few keystrokes are both the
        // least selective and the most expensive; without these, a query like
        // "at*" degrades into a full index scan.
        //
        // `remove_diacritics 2` folds accents at tokenize time, so "Bronte"
        // finds "Brontë" without the query layer folding anything itself.
        migrator.registerMigration("v28_books_fts") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE books_fts USING fts5(
                    title,
                    author,
                    description,
                    content='books',
                    content_rowid='rowid',
                    prefix='2 3',
                    tokenize='unicode61 remove_diacritics 2'
                )
                """)

            // Backfill existing libraries. 'rebuild' reads straight from the
            // content table — ~600ms for 50k books, single-digit ms for a
            // realistic library.
            try db.execute(sql: "INSERT INTO books_fts(books_fts) VALUES('rebuild')")

            // Keep the index in sync. `books` is hard-deleted (unlike
            // highlights/notes/bookmarks, which carry deletedAt), so a plain
            // AFTER DELETE trigger is sufficient — there is no soft-delete
            // state that would need filtering at query time.
            try db.execute(sql: """
                CREATE TRIGGER books_fts_ai AFTER INSERT ON books BEGIN
                    INSERT INTO books_fts(rowid, title, author, description)
                    VALUES (new.rowid, new.title, new.author, new.description);
                END
                """)
            // External-content indexes can't look up old values themselves —
            // the 'delete' command must be handed the previous column values
            // verbatim, or the index silently corrupts.
            try db.execute(sql: """
                CREATE TRIGGER books_fts_ad AFTER DELETE ON books BEGIN
                    INSERT INTO books_fts(books_fts, rowid, title, author, description)
                    VALUES ('delete', old.rowid, old.title, old.author, old.description);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER books_fts_au AFTER UPDATE ON books BEGIN
                    INSERT INTO books_fts(books_fts, rowid, title, author, description)
                    VALUES ('delete', old.rowid, old.title, old.author, old.description);
                    INSERT INTO books_fts(rowid, title, author, description)
                    VALUES (new.rowid, new.title, new.author, new.description);
                END
                """)
        }

        // v29 — cache the system fields of every record the server has seen.
        //
        // A CKRecord built from scratch carries no change tag, so CloudKit has
        // no way to tell an update from a blind overwrite: with
        // `.ifServerRecordUnchanged` (what CKSyncEngine uses) every save after
        // the first fails with `serverRecordChanged`. The previous engine
        // worked around this by forcing `.changedKeys`, which trades the
        // conflict for silent clobbering — the server's version is overwritten
        // without ever being looked at.
        //
        // Storing the system fields (change tag, record ID, zone, creation
        // metadata — never the user data) lets each push carry the tag of the
        // version it was derived from. Conflicts then mean what they should:
        // someone else really did change this record in the meantime, and the
        // three-way merge in SyncMerge runs against a real ancestor.
        migrator.registerMigration("v29_cloudkit_record_metadata") { db in
            try db.create(table: "cloudkit_record_metadata") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID", .text).notNull()
                // NSKeyedArchiver output of CKRecord.encodeSystemFields.
                t.column("systemFields", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["recordType", "recordID"])
            }
        }

        // v30 — partition reading activity by device.
        //
        // v24 made (bookID, date) unique, so a day could hold exactly one row
        // per book and two devices had to reconcile into it. The sync path
        // reconciled with max(duration): read 20 minutes on an iPhone and 15
        // on an iPad and the day recorded 20, not 35. Every multi-device day
        // under-reported, silently, and the Memory Garden's doodle tiers are
        // driven by that number.
        //
        // Adding the device to the key removes the reconciliation instead of
        // trying to get it right: each installation owns its own row, no row
        // ever has two writers, and a day's total is the sum across rows. That
        // is idempotent (re-pulling a row overwrites it with itself) and
        // commutative, which max was too but at the cost of being wrong.
        //
        // Existing rows are attributed to this device — the only device that
        // could have written them. See §3.4 of docs/sync-conflict-policy.md.
        migrator.registerMigration("v30_reading_activity_per_device") { db in
            try db.alter(table: "readingActivity") { t in
                t.add(column: "deviceID", .text).notNull().defaults(to: "")
            }
            try db.execute(sql: "UPDATE readingActivity SET deviceID = ? WHERE deviceID = ''",
                           arguments: [DeviceIdentity.current])

            try db.execute(sql: "DROP INDEX IF EXISTS idx_readingActivity_book_date")
            try db.create(index: "idx_readingActivity_book_date_device",
                          on: "readingActivity",
                          columns: ["bookID", "date", "deviceID"],
                          unique: true)
        }

        // v31 — make the CDC queue's recordID a usable CloudKit record name.
        //
        // The v21/v27 triggers wrote `NEW.id` straight into
        // cloudkit_pending_changes.recordID. GRDB encodes `UUID` as a 16-byte
        // blob, and SQLite's TEXT affinity does not convert a blob, so the
        // column held raw bytes. Reading it back into a Swift `String` either
        // produced mojibake (when the bytes happened to be valid UTF-8) or
        // threw, which poisoned the whole queue read.
        //
        // Either way the push path was dead: an unparseable local id fails
        // `UUID(uuidString:)`, `recordToSave` returns nil, and CKSyncEngine
        // drops the change. Nothing locally-originated could ever upload. It
        // failed closed, so no junk reached CloudKit — but nothing else did
        // either. Unnoticed because sync has never run.
        //
        // The triggers now format the blob as canonical uppercase UUID text,
        // matching Swift's `uuidString`. `hex()` already returns uppercase.
        // The typeof() guard covers ids that are already text: BookRepository's
        // touchLastReadAt carries a both-encodings fallback, so such rows may
        // exist.
        //
        // Composite membership keys also switch from "|" to "_". CloudKit
        // record names admit only ASCII letters, digits, "-", "_" and "." —
        // "|" was never legal, and CKRecordName expects "_".
        migrator.registerMigration("v31_cdc_record_ids_as_uuid_text") { db in
            let stamp = "strftime('%Y-%m-%dT%H:%M:%f', 'now')"

            // Upsert-only tables (soft-deletes, never hard-deleted).
            for table in ["highlights", "notes", "bookmarks", "saved_words", "readingActivity"] {
                let type = Self.cloudKitType(for: table)
                for (suffix, event, alias) in [("_ck_insert", "INSERT", "NEW"),
                                               ("_ck_update", "UPDATE", "NEW")] {
                    try db.execute(sql: "DROP TRIGGER IF EXISTS \(table)\(suffix)")
                    try db.execute(sql: """
                        CREATE TRIGGER \(table)\(suffix)
                        AFTER \(event) ON \(table)
                        BEGIN
                            INSERT OR REPLACE INTO cloudkit_pending_changes
                                (recordType, recordID, operation, queuedAt)
                            VALUES ('\(type)', \(Self.uuidTextSQL("\(alias).id")),
                                    'upsert', \(stamp));
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
                            VALUES ('\(type)', \(Self.uuidTextSQL("NEW.id")),
                                    'upsert', \(stamp));
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
                        VALUES ('\(type)', \(Self.uuidTextSQL("OLD.id")),
                                'delete', \(stamp));
                    END
                    """)
            }

            // bookCategoryMemberships — composite key "bookID_categoryID".
            let newComposite = "\(Self.uuidTextSQL("NEW.bookID")) || '_' || "
                + Self.uuidTextSQL("NEW.categoryID")
            let oldComposite = "\(Self.uuidTextSQL("OLD.bookID")) || '_' || "
                + Self.uuidTextSQL("OLD.categoryID")

            try db.execute(sql: "DROP TRIGGER IF EXISTS bookCategoryMemberships_ck_insert")
            try db.execute(sql: """
                CREATE TRIGGER bookCategoryMemberships_ck_insert
                AFTER INSERT ON bookCategoryMemberships
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('BookCategoryMembership', \(newComposite), 'upsert', \(stamp));
                END
                """)
            try db.execute(sql: "DROP TRIGGER IF EXISTS bookCategoryMemberships_ck_delete")
            try db.execute(sql: """
                CREATE TRIGGER bookCategoryMemberships_ck_delete
                AFTER DELETE ON bookCategoryMemberships
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('BookCategoryMembership', \(oldComposite), 'delete', \(stamp));
                END
                """)

            // Every queued row was written by the old triggers, so every one
            // carries an unusable recordID. Repairing them is not worth it:
            // rebuild the queue from what actually exists. Nothing is lost —
            // sync has never run, so all of it still needs pushing. Queued
            // deletes are dropped, which is correct for the same reason: the
            // server has no record to delete.
            try db.execute(sql: "DELETE FROM cloudkit_pending_changes")

            for (type, table) in [("Book", "books"),
                                  ("BookCategory", "bookCategories"),
                                  ("Highlight", "highlights"),
                                  ("Note", "notes"),
                                  ("Bookmark", "bookmarks"),
                                  ("SavedWord", "saved_words"),
                                  ("ReadingActivity", "readingActivity")] {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO cloudkit_pending_changes
                        (recordType, recordID, operation)
                    SELECT '\(type)', \(Self.uuidTextSQL("id")), 'upsert' FROM \(table)
                    """)
            }
            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes
                    (recordType, recordID, operation)
                SELECT 'BookCategoryMembership',
                       \(Self.uuidTextSQL("bookID")) || '_' || \(Self.uuidTextSQL("categoryID")),
                       'upsert'
                FROM bookCategoryMemberships
                """)
        }

        // v32 — shelf membership becomes a two-phase set.
        //
        // Removing a book from a shelf used to DELETE the row and queue a
        // CloudKit delete. A hard delete carries no timestamp, so a removal on
        // one device racing any write on another resolved by arrival order
        // rather than intent: the book reappeared on the shelf, or vanished
        // from it, depending on network timing. A device that was offline
        // during the removal cannot tell "removed remotely" from "not synced
        // yet" and re-adds it.
        //
        // With a tombstone the removal is a write like any other, ordered
        // against the rest, and final. Re-adding is an explicit clear of
        // deletedAt rather than a resurrection by merge. Annotations already
        // work this way. See §3.3 of docs/sync-conflict-policy.md.
        //
        // The membership table gains an update trigger for the first time:
        // removal is now an UPDATE, and without one it would never be queued.
        // The delete trigger stays for genuine hard deletes — the foreign keys
        // cascade when a book or a shelf is deleted outright, and those really
        // should remove the CloudKit record.
        migrator.registerMigration("v32_membership_tombstones") { db in
            try db.alter(table: "bookCategoryMemberships") { t in
                t.add(column: "deletedAt", .datetime)
            }

            let stamp = "strftime('%Y-%m-%dT%H:%M:%f', 'now')"
            let composite = "\(Self.uuidTextSQL("NEW.bookID")) || '_' || "
                + Self.uuidTextSQL("NEW.categoryID")

            try db.execute(sql: "DROP TRIGGER IF EXISTS bookCategoryMemberships_ck_update")
            try db.execute(sql: """
                CREATE TRIGGER bookCategoryMemberships_ck_update
                AFTER UPDATE ON bookCategoryMemberships
                BEGIN
                    INSERT OR REPLACE INTO cloudkit_pending_changes
                        (recordType, recordID, operation, queuedAt)
                    VALUES ('BookCategoryMembership', \(composite), 'upsert', \(stamp));
                END
                """)
        }

        // v33 — split the reader's completion data out of `books`.
        //
        // `books` mixed two things with opposite semantics: metadata extracted
        // from the EPUB at import, which is identical on every device and never
        // needs merging, and the reader's own rating and reflection, which are
        // genuinely editable on two devices at once. One record for both is
        // what forced the old sync path to guess — and a guess that cannot tell
        // "cleared" from "never set" is why a deleted reflection could not
        // propagate.
        //
        // Splitting makes the boundary structural instead of a convention:
        // Book is now immutable by construction, and every field on
        // BookCompletion is user-authored and honestly last-writer-wins.
        //
        // This is the last of the one-way doors. CloudKit's production schema
        // is additive-only, so a `Book` deployed carrying `rating` keeps that
        // field forever. See §3.1 of docs/sync-conflict-policy.md.
        migrator.registerMigration("v33_split_book_completion") { db in
            try db.create(table: "bookCompletions") { t in
                t.column("bookID", .text).notNull().primaryKey()
                    .references("books", onDelete: .cascade)
                t.column("rating", .integer)
                t.column("reflection", .text)
                t.column("reflectionImageFilename", .text)
                // A row exists only once the book has been finished.
                t.column("finishedAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
            }

            // Carry across whatever readers have already recorded. A book with
            // a rating or reflection but no finish date has no completion in
            // the new model, so it adopts its own modifiedAt as the date.
            try db.execute(sql: """
                INSERT INTO bookCompletions
                    (bookID, rating, reflection, reflectionImageFilename, finishedAt, modifiedAt)
                SELECT id, rating, reflection, reflectionImageFilename,
                       COALESCE(finishedAt, modifiedAt), modifiedAt
                FROM books
                WHERE finishedAt IS NOT NULL
                   OR rating IS NOT NULL
                   OR reflection IS NOT NULL
                   OR reflectionImageFilename IS NOT NULL
                """)

            for column in ["rating", "reflection", "reflectionImageFilename", "finishedAt"] {
                try db.alter(table: "books") { t in t.drop(column: column) }
            }

            // CDC triggers. The delete trigger matters: the foreign key
            // cascades when a book is deleted, and the CloudKit record has to
            // go with it.
            let stamp = "strftime('%Y-%m-%dT%H:%M:%f', 'now')"
            for (suffix, event, alias, op) in [("_ck_insert", "INSERT", "NEW", "upsert"),
                                               ("_ck_update", "UPDATE", "NEW", "upsert"),
                                               ("_ck_delete", "DELETE", "OLD", "delete")] {
                try db.execute(sql: "DROP TRIGGER IF EXISTS bookCompletions\(suffix)")
                try db.execute(sql: """
                    CREATE TRIGGER bookCompletions\(suffix)
                    AFTER \(event) ON bookCompletions
                    BEGIN
                        INSERT OR REPLACE INTO cloudkit_pending_changes
                            (recordType, recordID, operation, queuedAt)
                        VALUES ('BookCompletion', \(Self.uuidTextSQL("\(alias).bookID")),
                                '\(op)', \(stamp));
                    END
                    """)
            }

            try db.execute(sql: """
                INSERT OR IGNORE INTO cloudkit_pending_changes
                    (recordType, recordID, operation)
                SELECT 'BookCompletion', \(Self.uuidTextSQL("bookID")), 'upsert'
                FROM bookCompletions
                """)
        }

        // v34 — park fetched records whose parent has not arrived yet.
        //
        // Six synced tables carry a NOT NULL foreign key to `books`, and
        // CloudKit makes no promise about the order records arrive in. Sorting
        // each batch parents-first (see SyncEngine.applyRank) handles the
        // ordinary case, but a highlight can still arrive in an earlier batch
        // than the book it belongs to. Inserting it then throws, the throw is
        // caught, and the record is dropped — permanently, because CloudKit
        // does not redeliver it. The annotation simply never appears on that
        // device.
        //
        // A device that already holds every book cannot hit this, which is why
        // it survived testing on two established phones. A clean install —
        // every TestFlight tester — hits it on the first sync.
        //
        // Rather than drop, park the whole record here and retry when the
        // parent shows up.
        migrator.registerMigration("v34_cloudkit_deferred_applies") { db in
            try db.create(table: "cloudkit_deferred_applies") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID", .text).notNull()
                // The complete CKRecord, values included — NSKeyedArchiver
                // output, not just the system fields cached elsewhere.
                t.column("record", .blob).notNull()
                t.column("deferredAt", .datetime).notNull()
                t.primaryKey(["recordType", "recordID"])
            }
        }

        // v35 — rebuild every sync trigger around three rules.
        //
        // 1. Writes made *by sync* do not queue a push and do not restamp
        //    modifiedAt. Every trigger is guarded by `sync_apply_context`,
        //    which the apply path raises for the length of its transaction.
        //    Previously each apply fired the triggers and then deleted the
        //    queue row it had just produced — which also deleted any genuine
        //    local edit queued for the same record, and the stamp trigger
        //    replaced the remote `modifiedAt` with this device's clock.
        //
        // 2. `books` only queues (and only restamps) when a *synced* column
        //    changed. preprocessingStatus, aiAnalysisProgress, aiEnabled and
        //    backendBookID describe this device's copy of the file; changing
        //    them used to push the whole Book record, many times per import.
        //
        // 3. Every synced table has a delete trigger. Highlights, notes,
        //    bookmarks, saved words and reading activity were upsert-only, so
        //    when a book was deleted and the foreign keys cascaded, their
        //    CloudKit records were left behind for ever.
        //
        // The context is a counter, not a flag, so nested apply scopes compose.
        // Triggers treat a missing row as "not applying": failing open means a
        // redundant push, failing closed would mean silently not syncing.
        migrator.registerMigration("v35_sync_apply_context_triggers") { db in
            try db.execute(sql: """
                CREATE TABLE sync_apply_context (
                    id     INTEGER PRIMARY KEY CHECK (id = 1),
                    active INTEGER NOT NULL DEFAULT 0
                )
                """)
            try db.execute(sql: "INSERT INTO sync_apply_context (id, active) VALUES (1, 0)")

            let local = Self.notApplyingSyncSQL
            let stamp = "strftime('%Y-%m-%dT%H:%M:%f', 'now')"

            func queue(_ type: String, _ key: String, _ op: String) -> String {
                """
                INSERT OR REPLACE INTO cloudkit_pending_changes
                    (recordType, recordID, operation, queuedAt)
                VALUES ('\(type)', \(key), '\(op)', \(stamp));
                """
            }

            func replace(_ name: String, _ body: String) throws {
                try db.execute(sql: "DROP TRIGGER IF EXISTS \(name)")
                try db.execute(sql: body)
            }

            // Tables keyed on a single `id` column.
            let idTables = ["highlights", "notes", "bookmarks", "saved_words",
                            "readingActivity", "books", "bookCategories"]
            for table in idTables {
                let type = Self.cloudKitType(for: table)
                let newID = Self.uuidTextSQL("NEW.id")
                let oldID = Self.uuidTextSQL("OLD.id")
                let updateGuard = table == "books"
                    ? "\(local) AND (\(Self.bookSyncedColumnsChangedSQL))"
                    : local

                try replace("\(table)_ck_insert", """
                    CREATE TRIGGER \(table)_ck_insert
                    AFTER INSERT ON \(table)
                    WHEN \(local)
                    BEGIN
                        \(queue(type, newID, "upsert"))
                    END
                    """)
                try replace("\(table)_ck_update", """
                    CREATE TRIGGER \(table)_ck_update
                    AFTER UPDATE ON \(table)
                    WHEN \(updateGuard)
                    BEGIN
                        \(queue(type, newID, "upsert"))
                    END
                    """)
                try replace("\(table)_ck_delete", """
                    CREATE TRIGGER \(table)_ck_delete
                    AFTER DELETE ON \(table)
                    WHEN \(local)
                    BEGIN
                        \(queue(type, oldID, "delete"))
                    END
                    """)
                try replace("\(table)_stamp_modifiedAt", """
                    CREATE TRIGGER \(table)_stamp_modifiedAt
                    AFTER UPDATE ON \(table)
                    FOR EACH ROW
                    WHEN \(updateGuard)
                    BEGIN
                        UPDATE \(table) SET modifiedAt = \(stamp) WHERE id = NEW.id;
                    END
                    """)
            }

            // bookCompletions — keyed on the book it belongs to. No stamp
            // trigger: saveCompletion sets modifiedAt itself.
            for (suffix, event, alias, op) in [("_ck_insert", "INSERT", "NEW", "upsert"),
                                               ("_ck_update", "UPDATE", "NEW", "upsert"),
                                               ("_ck_delete", "DELETE", "OLD", "delete")] {
                try replace("bookCompletions\(suffix)", """
                    CREATE TRIGGER bookCompletions\(suffix)
                    AFTER \(event) ON bookCompletions
                    WHEN \(local)
                    BEGIN
                        \(queue("BookCompletion", Self.uuidTextSQL("\(alias).bookID"), op))
                    END
                    """)
            }

            // bookCategoryMemberships — composite key "bookID_categoryID".
            func composite(_ alias: String) -> String {
                "\(Self.uuidTextSQL("\(alias).bookID")) || '_' || "
                    + Self.uuidTextSQL("\(alias).categoryID")
            }
            for (suffix, event, alias, op) in [("_ck_insert", "INSERT", "NEW", "upsert"),
                                               ("_ck_update", "UPDATE", "NEW", "upsert"),
                                               ("_ck_delete", "DELETE", "OLD", "delete")] {
                try replace("bookCategoryMemberships\(suffix)", """
                    CREATE TRIGGER bookCategoryMemberships\(suffix)
                    AFTER \(event) ON bookCategoryMemberships
                    WHEN \(local)
                    BEGIN
                        \(queue("BookCategoryMembership", composite(alias), op))
                    END
                    """)
            }
            try replace("bookCategoryMemberships_stamp_modifiedAt", """
                CREATE TRIGGER bookCategoryMemberships_stamp_modifiedAt
                AFTER UPDATE ON bookCategoryMemberships
                FOR EACH ROW
                WHEN \(local)
                BEGIN
                    UPDATE bookCategoryMemberships
                    SET    modifiedAt = \(stamp)
                    WHERE  bookID = NEW.bookID AND categoryID = NEW.categoryID;
                END
                """)
        }

        return migrator
    }

    /// SQL producing canonical uppercase UUID text from a column that may hold
    /// either a 16-byte blob (how GRDB encodes `UUID`) or already-canonical
    /// text.
    ///
    /// SQLite's TEXT affinity does not convert a blob, so a UUID written by
    /// GRDB stays raw bytes in a `.text` column and reads back as mojibake.
    /// `hex()` returns uppercase, which is what `UUID.uuidString` produces, so
    /// no case folding is needed.
    nonisolated static func uuidTextSQL(_ column: String) -> String {
        """
        CASE WHEN typeof(\(column)) = 'blob' THEN
            substr(hex(\(column)), 1, 8) || '-' || substr(hex(\(column)), 9, 4) || '-' || \
        substr(hex(\(column)), 13, 4) || '-' || substr(hex(\(column)), 17, 4) || '-' || \
        substr(hex(\(column)), 21, 12)
        ELSE \(column) END
        """
    }

    /// Trigger guard: true unless the sync engine is applying remote changes
    /// in the current transaction. See migration v35 and `SyncApplyContext`.
    nonisolated static let notApplyingSyncSQL =
        "COALESCE((SELECT active FROM sync_apply_context WHERE id = 1), 0) = 0"

    /// Trigger guard for `books`: true when a column that travels on the Book
    /// record changed. Device-only columns (preprocessing, AI) and modifiedAt
    /// itself are deliberately absent.
    nonisolated static let bookSyncedColumns = [
        "title", "author", "format", "localFilename", "description", "language",
        "publisher", "coverFilename", "importDate", "contentHash",
        "estimatedPageCount", "estimatedReadingTimeMinutes", "lastReadAt"
    ]

    nonisolated static var bookSyncedColumnsChangedSQL: String {
        bookSyncedColumns.map { "OLD.\($0) IS NOT NEW.\($0)" }.joined(separator: " OR ")
    }

    // Maps a SQLite table name to its CloudKit record type string.
    // Kept here (alongside the migration that creates the triggers) so the
    // strings stay in sync automatically.
    static func cloudKitType(for tableName: String) -> String {
        switch tableName {
        case "books":                   return "Book"
        case "bookCategories":          return "BookCategory"
        case "bookCategoryMemberships": return "BookCategoryMembership"
        case "bookCompletions":         return "BookCompletion"
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
