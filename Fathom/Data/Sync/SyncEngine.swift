import CloudKit
import Foundation
import GRDB

// MARK: - Pending change row (mirrors cloudkit_pending_changes table)

private struct PendingChange: Decodable, FetchableRecord {
    let recordType: String
    let recordID: String
    let operation: String   // "upsert" | "delete"
    /// Raw column text, not a Date: cleanup deletes by exact
    /// (recordType, recordID, queuedAt) match, and round-tripping through
    /// Date would change the string format and never match.
    let queuedAt: String
}

// MARK: - SyncEngine

/// Observes the `cloudkit_pending_changes` CDC table and flushes records to
/// the CloudKit private database in the user's zone.
///
/// Lifecycle:
///   `start(userID:)`  — call after Supabase sign-in + iCloud configured
///   `stop()`          — call on sign-out
///
/// The engine is resilient: if a push fails the rows stay in
/// `cloudkit_pending_changes` and are retried on the next observation fire.
actor SyncEngine {

    // MARK: Shared instance

    static let shared = SyncEngine()
    private init() {}

    // MARK: State

    var zoneID: CKRecordZone.ID?               // internal: read by pull extension
    private var pushTask: Task<Void, Never>?
    private var cancellable: AnyDatabaseCancellable?
    private var isPushing = false
    private var notificationTokens: [NSObjectProtocol] = []

    var container: CKContainer {               // internal: used by pull extension
        CKContainer(identifier: "iCloud.com.Vardaan.Fathom")
    }
    var database: CKDatabase { container.privateCloudDatabase }  // internal: pull extension

    // MARK: - Lifecycle

    /// Call once after `ICloudFileStore.configure(userID:)` returns.
    func start(userID: UUID) async {
        let zoneName = userID.uuidString
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        // 1. Ensure the zone exists before any reads or writes.
        await ensureZoneExists()

        // 2. Register a silent push subscription (no-ops without push entitlement).
        await setupSubscription()

        // 3. Pull any changes that happened while the app was not running.
        await fetchChangesIfNeeded()

        // 4. Observe the CDC queue for outgoing pushes.
        startObservation()

        // 5. Push reading position and settings when they change locally.
        startNotificationObservers()

        AppLogger.log(tag: "SyncEngine", "Started for zone \(zoneName)")
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        pushTask?.cancel()
        pushTask = nil
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens = []
        zoneID = nil
        AppLogger.log(tag: "SyncEngine", "Stopped")
    }

    // MARK: - Notification observers (reading position + settings)

    private func startNotificationObservers() {
        let center = NotificationCenter.default

        let posToken = center.addObserver(
            forName: ReadingStateStore.didSaveNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let bookID = note.userInfo?["bookID"] as? UUID else { return }
            Task { await self?.pushReadingPosition(bookID: bookID) }
        }

        let settingsToken = center.addObserver(
            forName: ReaderSettingsStore.didSaveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.pushReaderSettings() }
        }

        let profileToken = center.addObserver(
            forName: UserProfileStore.didSaveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.pushUserProfile() }
        }

        notificationTokens = [posToken, settingsToken, profileToken]
    }

    // MARK: - Singleton-record save helper

    /// Saves a freshly constructed record with the `.changedKeys` policy.
    ///
    /// `CKDatabase.save` defaults to `.ifServerRecordUnchanged`, and a record
    /// built from scratch carries no server change tag — so once the record
    /// exists on the server, every subsequent save fails with
    /// `serverRecordChanged`. Reading position, reader settings, and user
    /// profile are last-write-wins singletons (conflicts are resolved by
    /// comparing timestamps on pull), so overwriting server keys is correct.
    private func saveOverwriting(_ record: CKRecord) async throws {
        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        var recordError: Error?
        op.perRecordSaveBlock = { _, result in
            if case .failure(let e) = result { recordError = e }
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            self.database.add(op)
        }
        if let recordError { throw recordError }
    }

    // MARK: - Reading position push

    func pushReadingPosition(bookID: UUID) async {
        guard let zoneID,
              let locatorJSON = ReadingStateStore.shared.locatorJSON(forBookID: bookID)
        else { return }

        let rid = CKRecord.ID(recordName: bookID.uuidString, zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.readingPosition, recordID: rid)
        r["bookID"]      = bookID.uuidString as CKRecordValue
        r["locatorJSON"] = locatorJSON as CKRecordValue
        r["savedAt"]     = (ReadingStateStore.shared.savedAt(forBookID: bookID) ?? Date()) as CKRecordValue

        do {
            try await saveOverwriting(r)
            AppLogger.log(tag: "SyncEngine", "Reading position pushed for book \(bookID)")
        } catch {
            AppLogger.log(tag: "SyncEngine", "Reading position push failed: \(error)")
        }
    }

    // MARK: - Reader settings push

    func pushReaderSettings() async {
        guard let zoneID else { return }

        let settings    = ReaderSettingsStore.shared.load()
        let modifiedAt  = ReaderSettingsStore.shared.modifiedAt ?? Date()
        guard let data  = try? JSONEncoder().encode(settings) else { return }

        let rid = CKRecord.ID(recordName: "readerSettings", zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.readerSettings, recordID: rid)
        r["settingsJSON"] = data as CKRecordValue
        r["modifiedAt"]   = modifiedAt as CKRecordValue

        do {
            try await saveOverwriting(r)
            AppLogger.log(tag: "SyncEngine", "Reader settings pushed")
        } catch {
            AppLogger.log(tag: "SyncEngine", "Reader settings push failed: \(error)")
        }
    }

    // MARK: - User profile push

    func pushUserProfile() async {
        guard let zoneID else { return }

        let profile    = UserProfileStore.shared.load()
        let modifiedAt = UserProfileStore.shared.modifiedAt ?? Date()

        let rid = CKRecord.ID(recordName: "userProfile", zoneID: zoneID)
        let r   = CKRecord(recordType: CKRecordType.userProfile, recordID: rid)
        if let name = profile.displayName  { r["displayName"]  = name as CKRecordValue }
        if let emoji = profile.avatarEmoji { r["avatarEmoji"]  = emoji as CKRecordValue }
        r["avatarColorHex"] = profile.avatarColorHex as CKRecordValue
        r["modifiedAt"]     = modifiedAt as CKRecordValue

        do {
            try await saveOverwriting(r)
            AppLogger.log(tag: "SyncEngine", "User profile pushed")
        } catch {
            AppLogger.log(tag: "SyncEngine", "User profile push failed: \(error)")
        }
    }

    // MARK: - Zone management

    private func ensureZoneExists() async {
        guard let zoneID else { return }
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)],
                                                     deleting: [])
            AppLogger.log(tag: "SyncEngine", "Zone ready: \(zoneID.zoneName)")
        } catch {
            AppLogger.log(tag: "SyncEngine", "Zone creation error: \(error)")
        }
    }

    // MARK: - CDC observation

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> [PendingChange] in
            try PendingChange.fetchAll(db, sql: """
                SELECT recordType, recordID, operation, queuedAt
                FROM   cloudkit_pending_changes
                ORDER  BY queuedAt ASC
                """)
        }

        cancellable = observation.start(
            in: DatabaseManager.shared.dbQueue,
            scheduling: .async(onQueue: .global(qos: .utility)),
            onError: { error in
                AppLogger.log(tag: "SyncEngine", "Observation error: \(error)")
            },
            onChange: { [weak self] rows in
                guard !rows.isEmpty else { return }
                Task { await self?.scheduleFlush() }
            }
        )
    }

    /// Debounce: if a flush is already in flight, do nothing — that flush's
    /// loop below picks up rows that arrive while it runs.
    private func scheduleFlush() async {
        guard !isPushing else { return }
        isPushing = true
        defer { isPushing = false }
        // Changes that land while a push is in flight have their observation
        // fire swallowed by the guard above, so keep flushing until a pass
        // makes no progress — queue empty, offline, or the remaining rows
        // persistently fail (those retry on the next observation/foreground).
        while await flush() > 0 {}
    }

    // MARK: - Push

    /// Pushes one batch of pending changes. Returns the number of queue rows
    /// successfully processed and cleared (0 = no progress; stop looping).
    private func flush() async -> Int {
        guard let zoneID else { return 0 }

        // Read the pending queue.
        let pending: [PendingChange]
        do {
            pending = try await DatabaseManager.shared.dbQueue.read { db in
                try PendingChange.fetchAll(db, sql: """
                    SELECT recordType, recordID, operation, queuedAt
                    FROM   cloudkit_pending_changes
                    ORDER  BY queuedAt ASC
                    """)
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Failed to read pending changes: \(error)")
            return 0
        }

        if pending.isEmpty { return 0 }

        let upserts = pending.filter { $0.operation == "upsert" }
        let deletes = pending.filter { $0.operation == "delete" }

        let records = await buildRecords(for: upserts, zoneID: zoneID)

        let deleteIDs = deletes.map {
            CKRecord.ID(recordName: $0.recordID, zoneID: zoneID)
        }

        guard !records.isEmpty || !deleteIDs.isEmpty else {
            // Nothing to push — clear stale queue rows.
            await clearQueue(pending)
            return pending.count
        }

        // Push to CloudKit.
        do {
            let op = CKModifyRecordsOperation(recordsToSave: records,
                                              recordIDsToDelete: deleteIDs)
            op.savePolicy = .changedKeys   // only push fields we set, respect server changes
            op.isAtomic   = false          // partial success is fine

            var savedIDs    = Set<String>()
            var deletedIDs  = Set<String>()
            var failedTypes = [String: Error]()

            op.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success: savedIDs.insert(recordID.recordName)
                case .failure(let e):
                    AppLogger.log(tag: "SyncEngine",
                                  "Save failed for \(recordID.recordName): \(e)")
                    failedTypes[recordID.recordName] = e
                }
            }
            op.perRecordDeleteBlock = { recordID, result in
                switch result {
                case .success: deletedIDs.insert(recordID.recordName)
                case .failure(let e):
                    AppLogger.log(tag: "SyncEngine",
                                  "Delete failed for \(recordID.recordName): \(e)")
                }
            }
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
                self.database.add(op)
            }

            // Remove only successfully processed rows from the queue.
            let succeeded = pending.filter {
                savedIDs.contains($0.recordID) || deletedIDs.contains($0.recordID)
            }
            await clearQueue(succeeded)

            let total = savedIDs.count + deletedIDs.count
            AppLogger.log(tag: "SyncEngine",
                          "Flushed \(total)/\(pending.count) records to CloudKit")
            return succeeded.count

        } catch {
            AppLogger.log(tag: "SyncEngine", "Flush error: \(error)")
            return 0
        }
    }

    // MARK: - Record building

    /// Fetches the live rows for the given pending-change list and converts
    /// them to CKRecords.  Returns an empty array for record types that can't
    /// be found (already deleted locally, etc.).
    private func buildRecords(for pending: [PendingChange],
                              zoneID: CKRecordZone.ID) async -> [CKRecord] {
        var records: [CKRecord] = []

        // Group by recordType to batch DB reads.
        let grouped = Dictionary(grouping: pending, by: \.recordType)

        for (type, items) in grouped {
            let ids = items.map(\.recordID)
            do {
                let fetched = try await DatabaseManager.shared.dbQueue.read { db -> [CKRecord] in
                    switch type {
                    case CKRecordType.book:
                        return try Book.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.bookCategory:
                        return try BookCategory.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.bookCategoryMembership:
                        return try BookCategoryMembership.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.highlight:
                        return try Highlight.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.note:
                        return try Note.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.bookmark:
                        return try Bookmark.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.savedWord:
                        return try SavedWord.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.readingActivity:
                        return try ReadingActivity.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    case CKRecordType.aiConversation:
                        // Dormant: chats currently live in ai_threads.json
                        // (AIThreadStore), not in the aiConversations tables this
                        // reads from. Migration v26 drops the CDC triggers; this
                        // guard covers rows queued by older builds.
                        guard FeatureFlags.aiCompanionEnabled else { return [] }
                        return try AIThread.fetchAll(db: db, ids: ids, zoneID: zoneID)
                    default:
                        return []
                    }
                }
                records.append(contentsOf: fetched)
            } catch {
                AppLogger.log(tag: "SyncEngine", "Build records error for \(type): \(error)")
            }
        }

        return records
    }

    // MARK: - Queue helpers

    /// Removes processed rows from the queue.
    ///
    /// Matches on queuedAt too: if a record was edited *while* its push was in
    /// flight, the trigger re-queued it with a fresh (millisecond-precision)
    /// timestamp — that row must survive this cleanup so the newer change is
    /// pushed by the next pass.
    private func clearQueue(_ processed: [PendingChange]) async {
        guard !processed.isEmpty else { return }
        do {
            try await DatabaseManager.shared.dbQueue.write { db in
                for item in processed {
                    try db.execute(
                        sql: """
                            DELETE FROM cloudkit_pending_changes
                            WHERE recordType = ? AND recordID = ? AND queuedAt = ?
                            """,
                        arguments: [item.recordType, item.recordID, item.queuedAt]
                    )
                }
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Queue cleanup error: \(error)")
        }
    }
}

// MARK: - Push-loop prevention (called by pull extension in the same transaction)

extension SyncEngine {
    /// Removes a CDC entry from within an already-open GRDB write transaction
    /// so pulled records are not immediately re-pushed.
    static func removeFromQueue(db: Database, type: String, id: String) {
        do {
            try db.execute(
                sql: "DELETE FROM cloudkit_pending_changes WHERE recordType = ? AND recordID = ?",
                arguments: [type, id]
            )
        } catch {
            // Non-fatal: the record would be re-pushed once, and LWW on the
            // other side makes that a no-op — but it shouldn't go unnoticed.
            AppLogger.log(tag: "SyncEngine", "removeFromQueue failed for \(type)/\(id): \(error)")
        }
    }
}

// MARK: - Batch fetch helpers
// Each model type gets a helper that reads all rows matching the given
// recordIDs from the local DB and converts them to CKRecords.

private extension Book {
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr),
                  let book = try Book.fetchOne(db, key: uuid) else { return nil }
            return book.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension BookCategory {
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr),
                  let cat = try BookCategory.fetchOne(db, key: uuid) else { return nil }
            return cat.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension BookCategoryMembership {
    // recordID is "bookUUID|categoryUUID"
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { compositeID -> CKRecord? in
            let parts = compositeID.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let bookID     = UUID(uuidString: parts[0]),
                  let categoryID = UUID(uuidString: parts[1]) else { return nil }
            let membership = try BookCategoryMembership
                .filter(Column("bookID") == bookID && Column("categoryID") == categoryID)
                .fetchOne(db)
            return membership?.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension Highlight {
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr),
                  let h = try Highlight.fetchOne(db, id: uuid) else { return nil }
            return h.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension Note {
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr),
                  let n = try Note.fetchOne(db, id: uuid) else { return nil }
            return n.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension Bookmark {
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr),
                  let b = try Bookmark.fetchOne(db, id: uuid) else { return nil }
            return b.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension SavedWord {
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr),
                  let w = try SavedWord.fetchOne(db, id: uuid) else { return nil }
            return w.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension ReadingActivity {
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr),
                  let a = try ReadingActivity.fetchOne(db, id: uuid) else { return nil }
            return a.toCKRecord(zoneID: zoneID)
        }
    }
}

private extension AIThread {
    // Fetches the conversation and its messages, then converts to one CKRecord.
    static func fetchAll(db: Database, ids: [String], zoneID: CKRecordZone.ID) throws -> [CKRecord] {
        try ids.compactMap { idStr -> CKRecord? in
            guard let uuid = UUID(uuidString: idStr) else { return nil }
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, bookID, passageText, locatorJSON, chapterTitle, createdAt
                FROM   aiConversations
                WHERE  id = ?
                """, arguments: [uuid.uuidString]) else { return nil }

            guard
                let idStr2      = row["id"] as? String,
                let id          = UUID(uuidString: idStr2),
                let bookIDStr   = row["bookID"] as? String,
                let bookID      = UUID(uuidString: bookIDStr),
                let passageText = row["passageText"] as? String,
                let createdAt   = row["createdAt"] as? Date
            else { return nil }

            let msgRows = try Row.fetchAll(db, sql: """
                SELECT id, role, content, createdAt
                FROM   aiMessages
                WHERE  conversationID = ?
                ORDER  BY createdAt ASC
                """, arguments: [uuid.uuidString])

            let messages: [AIMessage] = msgRows.compactMap { mr in
                guard
                    let idStr = mr["id"] as? String,
                    let msgID = UUID(uuidString: idStr),
                    let roleRaw = mr["role"] as? String,
                    let role = AIMessageRole(rawValue: roleRaw),
                    let content = mr["content"] as? String,
                    let ts = mr["createdAt"] as? Date
                else { return nil }
                return AIMessage(id: msgID, role: role, content: content, createdAt: ts)
            }

            let thread = AIThread(
                id: id,
                bookID: bookID,
                passageText: passageText,
                locatorJSON: row["locatorJSON"] as? String,
                chapterTitle: row["chapterTitle"] as? String,
                createdAt: createdAt,
                messages: messages
            )
            return thread.toCKRecord(zoneID: zoneID)
        }
    }
}
