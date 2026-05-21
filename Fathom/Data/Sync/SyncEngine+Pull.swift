import CloudKit
import Foundation
import GRDB
import ReadiumShared

// MARK: - SyncEngine pull path

extension SyncEngine {

    // MARK: - Subscription

    /// Registers a silent CKDatabaseSubscription.
    /// Fails gracefully when push notification entitlement is absent.
    func setupSubscription() async {
        guard let zoneID else { return }
        let subID = "fathom-zone-\(zoneID.zoneName)"

        do {
            // Check if already registered.
            _ = try await database.subscription(for: subID)
            AppLogger.log(tag: "SyncEngine", "Subscription already registered")
            return
        } catch { }   // not found — register it

        let sub = CKDatabaseSubscription(subscriptionID: subID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent background push
        sub.notificationInfo = info

        do {
            _ = try await database.modifySubscriptions(saving: [sub], deleting: [])
            AppLogger.log(tag: "SyncEngine", "CloudKit subscription registered: \(subID)")
        } catch {
            // Expected failure without push notification entitlement (Personal Team).
            AppLogger.log(tag: "SyncEngine",
                          "Subscription setup skipped (entitlement required): \(error)")
        }
    }

    // MARK: - Public entry point

    /// Fetches and applies all remote changes since the last server change token.
    /// Safe to call on foreground, after a push notification, or at startup.
    func fetchChangesIfNeeded() async {
        guard zoneID != nil else { return }
        await fetchChanges()
    }

    // MARK: - Core fetch

    func fetchChanges() async {
        guard let zoneID else { return }

        AppLogger.log(tag: "SyncEngine", "Fetching remote changes…")

        let tokenKey    = tokenKey(for: zoneID)
        let storedToken = loadToken(key: tokenKey)

        var changedRecords: [(CKRecord)] = []
        var deletedRecords: [(CKRecord.ID, CKRecord.RecordType)] = []
        var newToken: CKServerChangeToken?

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = storedToken

        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: config]
        )
        op.fetchAllChanges = true

        op.recordWasChangedBlock = { _, result in
            if case .success(let r) = result { changedRecords.append(r) }
        }
        op.recordWithIDWasDeletedBlock = { id, type in
            deletedRecords.append((id, type))
        }
        op.recordZoneFetchResultBlock = { _, result in
            if case .success(let (token, _, _)) = result { newToken = token }
        }

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                op.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
                self.database.add(op)
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "fetchChanges error: \(error)")
            return
        }

        AppLogger.log(tag: "SyncEngine",
                      "Pull received \(changedRecords.count) changed, "
                      + "\(deletedRecords.count) deleted")

        for record in changedRecords {
            await apply(changedRecord: record, zoneID: zoneID)
        }
        for (id, type) in deletedRecords {
            await apply(deletedID: id, type: type)
        }

        if let newToken {
            saveToken(newToken, key: tokenKey)
        }
    }

    // MARK: - Apply changed record

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func apply(changedRecord r: CKRecord, zoneID: CKRecordZone.ID) async {
        let recordName = r.recordID.recordName

        do {
            switch r.recordType {

            // ── Books ──────────────────────────────────────────────────────
            case CKRecordType.book:
                guard let incoming = Book.from(ckRecord: r) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    if let existing = try Book.fetchOne(db, key: incoming.id) {
                        if incoming.modifiedAt > existing.modifiedAt {
                            try incoming.update(db)
                        }
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.book, id: recordName)
                }

            // ── Book categories ────────────────────────────────────────────
            case CKRecordType.bookCategory:
                guard let incoming = BookCategory.from(ckRecord: r) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    if let existing = try BookCategory.fetchOne(db, key: incoming.id) {
                        if incoming.modifiedAt > existing.modifiedAt {
                            try incoming.update(db)
                        }
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.bookCategory, id: recordName)
                }

            // ── Category memberships ───────────────────────────────────────
            case CKRecordType.bookCategoryMembership:
                guard let incoming = BookCategoryMembership.from(ckRecord: r) else { return }
                let compositeID = incoming.ckRecordName
                try await DatabaseManager.shared.dbQueue.write { db in
                    let existing = try BookCategoryMembership
                        .filter(Column("bookID") == incoming.bookID
                                && Column("categoryID") == incoming.categoryID)
                        .fetchOne(db)
                    if let existing {
                        if incoming.modifiedAt > existing.modifiedAt {
                            try incoming.update(db)
                        }
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }
                    SyncEngine.removeFromQueue(db: db,
                                               type: CKRecordType.bookCategoryMembership,
                                               id: compositeID)
                }

            // ── Annotations (soft-delete tombstones propagate via deletedAt) ─
            case CKRecordType.highlight:
                guard let incoming = Highlight.from(ckRecord: r) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    if let existing = try Highlight.fetchOne(db, id: incoming.id) {
                        if incoming.modifiedAt > existing.modifiedAt {
                            try incoming.update(db)
                        }
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.highlight, id: recordName)
                }

            case CKRecordType.note:
                guard let incoming = Note.from(ckRecord: r) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    if let existing = try Note.fetchOne(db, id: incoming.id) {
                        if incoming.modifiedAt > existing.modifiedAt {
                            try incoming.update(db)
                        }
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.note, id: recordName)
                }

            case CKRecordType.bookmark:
                guard let incoming = Bookmark.from(ckRecord: r) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    if let existing = try Bookmark.fetchOne(db, id: incoming.id) {
                        if incoming.modifiedAt > existing.modifiedAt {
                            try incoming.update(db)
                        }
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.bookmark, id: recordName)
                }

            case CKRecordType.savedWord:
                guard let incoming = SavedWord.from(ckRecord: r) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    if let existing = try SavedWord.fetchOne(db, id: incoming.id) {
                        if incoming.modifiedAt > existing.modifiedAt {
                            try incoming.update(db)
                        }
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.savedWord, id: recordName)
                }

            // ── AI conversations (additive, never deleted) ─────────────────
            case CKRecordType.aiConversation:
                guard let incoming = AIThread.from(ckRecord: r) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    let exists = try Row.fetchOne(db,
                        sql: "SELECT 1 FROM aiConversations WHERE id = ?",
                        arguments: [incoming.id.uuidString]) != nil
                    guard !exists else {
                        SyncEngine.removeFromQueue(db: db,
                                                   type: CKRecordType.aiConversation,
                                                   id: recordName)
                        return
                    }
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO aiConversations
                            (id, bookID, paragraphID, passageText, locatorJSON, chapterTitle, createdAt)
                        VALUES (?, ?, 0, ?, ?, ?, ?)
                        """, arguments: [
                            incoming.id.uuidString,
                            incoming.bookID.uuidString,
                            incoming.passageText,
                            incoming.locatorJSON,
                            incoming.chapterTitle,
                            incoming.createdAt
                        ])
                    for msg in incoming.messages {
                        try db.execute(sql: """
                            INSERT OR IGNORE INTO aiMessages
                                (id, conversationID, role, content, createdAt)
                            VALUES (?, ?, ?, ?, ?)
                            """, arguments: [
                                msg.id.uuidString,
                                incoming.id.uuidString,
                                msg.role.rawValue,
                                msg.content,
                                msg.createdAt
                            ])
                    }
                    SyncEngine.removeFromQueue(db: db,
                                               type: CKRecordType.aiConversation,
                                               id: recordName)
                }

            // ── Reading position ───────────────────────────────────────────
            case CKRecordType.readingPosition:
                guard
                    let bookIDStr  = r["bookID"] as? String,
                    let bookID     = UUID(uuidString: bookIDStr),
                    let locatorJSON = r["locatorJSON"] as? String,
                    let savedAt    = r["savedAt"] as? Date
                else { return }

                let localDate = ReadingStateStore.shared.savedAt(forBookID: bookID)
                if localDate == nil || savedAt > localDate! {
                    if let locator = try? Locator(jsonString: locatorJSON) {
                        // suppressSync: true prevents an immediate re-push.
                        ReadingStateStore.shared.saveLocator(locator,
                                                             forBookID: bookID,
                                                             suppressSync: true)
                    }
                }

            // ── Reader settings ────────────────────────────────────────────
            case CKRecordType.readerSettings:
                guard
                    let data       = r["settingsJSON"] as? Data,
                    let settings   = try? JSONDecoder().decode(ReaderSettings.self, from: data),
                    let modifiedAt = r["modifiedAt"] as? Date
                else { return }

                let localDate = ReaderSettingsStore.shared.modifiedAt
                if localDate == nil || modifiedAt > localDate! {
                    ReaderSettingsStore.shared.save(settings, suppressSync: true)
                }

            default:
                break
            }
        } catch {
            AppLogger.log(tag: "SyncEngine",
                          "Apply failed for \(r.recordType)/\(recordName): \(error)")
        }
    }

    // MARK: - Apply deleted record (hard-delete notification from CloudKit)

    private func apply(deletedID id: CKRecord.ID, type: CKRecord.RecordType) async {
        let recordName = id.recordName
        do {
            switch type {
            case CKRecordType.book:
                guard let bookID = UUID(uuidString: recordName) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    _ = try Book.deleteOne(db, key: bookID)
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.book, id: recordName)
                }

            case CKRecordType.bookCategory:
                guard let catID = UUID(uuidString: recordName) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    _ = try BookCategory.deleteOne(db, key: catID)
                    SyncEngine.removeFromQueue(db: db, type: CKRecordType.bookCategory, id: recordName)
                }

            case CKRecordType.bookCategoryMembership:
                // recordName is "bookUUID|categoryUUID"
                let parts = recordName.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let bookID     = UUID(uuidString: parts[0]),
                      let categoryID = UUID(uuidString: parts[1]) else { return }
                try await DatabaseManager.shared.dbQueue.write { db in
                    try BookCategoryMembership
                        .filter(Column("bookID") == bookID && Column("categoryID") == categoryID)
                        .deleteAll(db)
                    SyncEngine.removeFromQueue(db: db,
                                               type: CKRecordType.bookCategoryMembership,
                                               id: recordName)
                }

            default:
                break  // Annotations use soft-delete — never reach this path.
            }
        } catch {
            AppLogger.log(tag: "SyncEngine",
                          "Hard-delete failed for \(type)/\(recordName): \(error)")
        }
    }

    // MARK: - Token management

    private func tokenKey(for zoneID: CKRecordZone.ID) -> String {
        "fathom.ck_server_token.\(zoneID.zoneName)"
    }

    private func loadToken(key: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken, key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
