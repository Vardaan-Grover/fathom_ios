import CloudKit
import Foundation
import GRDB
import ReadiumShared

// MARK: - Building records to push

extension SyncEngine {

    /// Produces the record CloudKit should save for this ID, or nil when the
    /// row no longer exists locally (CKSyncEngine then drops it from pending).
    ///
    /// The record is seeded from the cached system fields where we have them,
    /// so the save carries the change tag of the version it was derived from.
    /// Only when the server has never seen the record is a fresh one created.
    func recordToSave(_ recordID: CKRecord.ID) async -> CKRecord? {
        guard let parsed = CKRecordName.parse(recordID.recordName) else { return nil }
        let (type, localID) = parsed

        // Singletons live in file-backed stores, not SQLite.
        switch type {
        case CKRecordType.readingPosition:
            return await positionRecord(recordID, localID: localID)
        case CKRecordType.readerSettings:
            return await settingsRecord(recordID)
        case CKRecordType.userProfile:
            return await profileRecord(recordID)
        default:
            break
        }

        return try? await DatabaseManager.shared.dbQueue.read { db in
            guard let syncable = try Self.localModel(db: db, type: type, localID: localID) else {
                return nil
            }
            let record = try Self.seededRecord(db: db, type: type, recordID: recordID)
            syncable.apply(to: record)
            return record
        }
    }

    /// A record carrying the server's system fields when we have them.
    private static func seededRecord(db: Database,
                                     type: CKRecord.RecordType,
                                     recordID: CKRecord.ID) throws -> CKRecord {
        if let cached = try SyncRecordMetadata.lastKnownRecord(db: db,
                                                              type: type,
                                                              recordName: recordID.recordName) {
            return cached
        }
        return CKRecord(recordType: type, recordID: recordID)
    }

    /// Loads the local row behind a record ID.
    private static func localModel(db: Database,
                                   type: CKRecord.RecordType,
                                   localID: String) throws -> (any CloudKitSyncable)? {
        switch type {
        case CKRecordType.book:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try Book.fetchOne(db, key: uuid)

        case CKRecordType.bookCategory:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try BookCategory.fetchOne(db, key: uuid)

        case CKRecordType.bookCategoryMembership:
            guard let parts = CKRecordName.parseMembership(localID: localID) else { return nil }
            return try BookCategoryMembership
                .filter(Column("bookID") == parts.bookID && Column("categoryID") == parts.categoryID)
                .fetchOne(db)

        case CKRecordType.highlight:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try Highlight.fetchOne(db, id: uuid)

        case CKRecordType.note:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try Note.fetchOne(db, id: uuid)

        case CKRecordType.bookmark:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try Bookmark.fetchOne(db, id: uuid)

        case CKRecordType.savedWord:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try SavedWord.fetchOne(db, id: uuid)

        case CKRecordType.readingActivity:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try ReadingActivity.fetchOne(db, id: uuid)

        default:
            return nil
        }
    }

    // MARK: - Singleton records

    private func positionRecord(_ recordID: CKRecord.ID, localID: String) async -> CKRecord? {
        guard let bookID = UUID(uuidString: localID),
              let state = ReadingStateStore.shared.state(forBookID: bookID)
        else { return nil }

        let record = (try? await DatabaseManager.shared.dbQueue.read { db in
            try Self.seededRecord(db: db, type: CKRecordType.readingPosition, recordID: recordID)
        }) ?? CKRecord(recordType: CKRecordType.readingPosition, recordID: recordID)

        record["bookID"] = bookID.uuidString
        record["locatorJSON"] = state.locatorJSON
        record["savedAt"] = state.savedAt
        record["furthestProgression"] = state.furthestProgression
        return record
    }

    private func settingsRecord(_ recordID: CKRecord.ID) async -> CKRecord? {
        let settings = ReaderSettingsStore.shared.load()
        guard let data = try? JSONEncoder().encode(settings) else { return nil }

        let record = (try? await DatabaseManager.shared.dbQueue.read { db in
            try Self.seededRecord(db: db, type: CKRecordType.readerSettings, recordID: recordID)
        }) ?? CKRecord(recordType: CKRecordType.readerSettings, recordID: recordID)

        record["settingsJSON"] = data
        record["modifiedAt"] = ReaderSettingsStore.shared.modifiedAt ?? Date()
        return record
    }

    private func profileRecord(_ recordID: CKRecord.ID) async -> CKRecord? {
        let profile = UserProfileStore.shared.load()

        let record = (try? await DatabaseManager.shared.dbQueue.read { db in
            try Self.seededRecord(db: db, type: CKRecordType.userProfile, recordID: recordID)
        }) ?? CKRecord(recordType: CKRecordType.userProfile, recordID: recordID)

        record["displayName"] = profile.displayName
        record["avatarEmoji"] = profile.avatarEmoji
        record["avatarColorHex"] = profile.avatarColorHex
        record["modifiedAt"] = UserProfileStore.shared.modifiedAt ?? Date()
        return record
    }
}

// MARK: - Applying fetched changes

extension SyncEngine {

    func applyFetched(modifications: [CKDatabase.RecordZoneChange.Modification],
                      deletions: [CKDatabase.RecordZoneChange.Deletion]) async {

        // Records with an unsent local change are deliberately left alone.
        //
        // Writing the server's version over an edit that has not been pushed
        // yet would lose it twice over: once locally, and again when the
        // pending push rebuilds its record from the database it just
        // overwrote. Skipping the write *and* the system-field cache means the
        // push still goes out carrying the old change tag, so CloudKit answers
        // with `serverRecordChanged` and a real ancestor, and the merge runs
        // where it can actually be done correctly.
        let pendingNames = pendingSaveRecordNames()

        for modification in modifications {
            let record = modification.record
            let name = record.recordID.recordName
            guard CKRecordName.parse(name) != nil else { continue }
            if pendingNames.contains(name) {
                AppLogger.log(tag: "SyncEngine", "Deferring \(name) to push-side merge")
                continue
            }
            await apply(record: record, cacheSystemFields: true)
        }

        for deletion in deletions {
            await applyDeletion(deletion)
        }
    }

    /// Writes a merged record into the local database without caching system
    /// fields — the merged version has not been accepted by the server yet.
    func applyMerged(_ record: CKRecord) async {
        await apply(record: record, cacheSystemFields: false)
    }

    private func pendingSaveRecordNames() -> Set<String> {
        guard let engine = currentEngine else { return [] }
        var names = Set<String>()
        for change in engine.state.pendingRecordZoneChanges {
            if case .saveRecord(let id) = change { names.insert(id.recordName) }
        }
        return names
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func apply(record: CKRecord, cacheSystemFields: Bool) async {
        guard let parsed = CKRecordName.parse(record.recordID.recordName) else { return }
        let (type, localID) = parsed

        // Singletons are not database rows.
        switch type {
        case CKRecordType.readingPosition:
            applyReadingPosition(record)
            if cacheSystemFields { await cacheFields(record) }
            return
        case CKRecordType.readerSettings:
            applyReaderSettings(record)
            if cacheSystemFields { await cacheFields(record) }
            return
        case CKRecordType.userProfile:
            applyUserProfile(record)
            if cacheSystemFields { await cacheFields(record) }
            return
        default:
            break
        }

        do {
            try await DatabaseManager.shared.dbQueue.write { db in
                switch type {

                case CKRecordType.book:
                    guard let incoming = Book.from(ckRecord: record) else { return }
                    if let existing = try Book.fetchOne(db, key: incoming.id) {
                        var merged = incoming
                        // Fields that describe this device's copy of the file
                        // are never carried on the record — keep the local
                        // values rather than resetting them. (§3.2)
                        merged.preprocessingStatus = existing.preprocessingStatus
                        merged.aiAnalysisProgress  = existing.aiAnalysisProgress
                        merged.aiEnabled           = existing.aiEnabled
                        merged.backendBookID       = existing.backendBookID
                        try merged.update(db)
                    } else {
                        try incoming.insert(db, onConflict: .ignore)
                    }

                // `save` rather than `upsert` throughout: GRDB's upsert emits
                // ON CONFLICT DO UPDATE, and a statement carrying its own
                // conflict clause overrides the conflict resolution inside any
                // trigger it fires — which turns the CDC trigger's
                // `INSERT OR REPLACE INTO cloudkit_pending_changes` into a
                // plain INSERT and makes it fail whenever a change is already
                // queued for that record. `save` is UPDATE-then-INSERT with no
                // conflict clause.
                case CKRecordType.bookCategory:
                    guard let incoming = BookCategory.from(ckRecord: record) else { return }
                    try incoming.save(db)

                case CKRecordType.bookCategoryMembership:
                    guard let incoming = BookCategoryMembership.from(ckRecord: record) else { return }
                    try incoming.save(db)

                case CKRecordType.highlight:
                    guard let incoming = Highlight.from(ckRecord: record) else { return }
                    try incoming.save(db)

                case CKRecordType.note:
                    guard let incoming = Note.from(ckRecord: record) else { return }
                    try incoming.save(db)

                case CKRecordType.bookmark:
                    guard let incoming = Bookmark.from(ckRecord: record) else { return }
                    try incoming.save(db)

                case CKRecordType.savedWord:
                    guard let incoming = SavedWord.from(ckRecord: record) else { return }
                    try incoming.save(db)

                case CKRecordType.readingActivity:
                    guard let incoming = ReadingActivity.from(ckRecord: record) else { return }
                    try incoming.save(db)

                default:
                    return
                }

                // The write above fired the CDC trigger. Clear it, or this
                // device immediately pushes back what it just pulled.
                SyncEngine.removeFromQueue(db: db, type: type, id: localID)

                if cacheSystemFields {
                    try SyncRecordMetadata.save(db: db, record: record)
                }
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Apply failed for \(type)/\(localID): \(error)")
        }
    }

    private func cacheFields(_ record: CKRecord) async {
        try? await DatabaseManager.shared.dbQueue.write { db in
            try SyncRecordMetadata.save(db: db, record: record)
        }
    }

    // MARK: - Singleton apply

    private func applyReadingPosition(_ record: CKRecord) {
        guard
            let bookIDStr = record["bookID"] as? String,
            let bookID = UUID(uuidString: bookIDStr),
            let locatorJSON = record["locatorJSON"] as? String,
            let savedAt = record["savedAt"] as? Date
        else { return }

        // Position and furthest progress resolve independently — the store
        // owns that decision so it happens atomically with the write. An older
        // remote position loses, but the progress it carries can still raise
        // the high-water mark. See §3.6.
        ReadingStateStore.shared.applyRemoteState(
            locatorJSON: locatorJSON,
            savedAt: savedAt,
            furthestProgression: record["furthestProgression"] as? Double ?? 0,
            forBookID: bookID)
    }

    private func applyReaderSettings(_ record: CKRecord) {
        guard
            let data = record["settingsJSON"] as? Data,
            let incoming = try? JSONDecoder().decode(ReaderSettings.self, from: data),
            let modifiedAt = record["modifiedAt"] as? Date
        else { return }

        let local = ReaderSettingsStore.shared.modifiedAt
        guard local == nil || modifiedAt > local! else { return }
        ReaderSettingsStore.shared.save(incoming, suppressSync: true)
    }

    private func applyUserProfile(_ record: CKRecord) {
        guard let modifiedAt = record["modifiedAt"] as? Date else { return }
        let local = UserProfileStore.shared.modifiedAt
        guard local == nil || modifiedAt > local! else { return }

        var profile = UserProfileStore.shared.load()
        profile.displayName = record["displayName"] as? String
        profile.avatarEmoji = record["avatarEmoji"] as? String
        if let hex = record["avatarColorHex"] as? String { profile.avatarColorHex = hex }
        UserProfileStore.shared.save(profile, suppressSync: true)
    }

    // MARK: - Deletions

    private func applyDeletion(_ deletion: CKDatabase.RecordZoneChange.Deletion) async {
        guard let parsed = CKRecordName.parse(deletion.recordID.recordName) else { return }
        let (type, localID) = parsed

        do {
            try await DatabaseManager.shared.dbQueue.write { db in
                switch type {
                case CKRecordType.book:
                    if let uuid = UUID(uuidString: localID) {
                        _ = try Book.deleteOne(db, key: uuid)
                    }
                case CKRecordType.bookCategory:
                    if let uuid = UUID(uuidString: localID) {
                        _ = try BookCategory.deleteOne(db, key: uuid)
                    }
                case CKRecordType.bookCategoryMembership:
                    if let parts = CKRecordName.parseMembership(localID: localID) {
                        _ = try BookCategoryMembership
                            .filter(Column("bookID") == parts.bookID
                                    && Column("categoryID") == parts.categoryID)
                            .deleteAll(db)
                    }
                default:
                    // Annotations soft-delete via deletedAt and should never
                    // arrive here.
                    AppLogger.log(tag: "SyncEngine",
                                  "Unexpected hard delete for \(type)/\(localID)")
                }
                SyncEngine.removeFromQueue(db: db, type: type, id: localID)
                try SyncRecordMetadata.delete(db: db,
                                              type: type,
                                              recordName: deletion.recordID.recordName)
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Delete apply failed for \(type)/\(localID): \(error)")
        }
    }

    // MARK: - Full re-upload

    /// Queues every local row for push. Used when the zone has been recreated
    /// and the server has nothing.
    func enqueueEverything() async {
        do {
            let rows = try await DatabaseManager.shared.dbQueue.read { db -> [(String, String)] in
                var out: [(String, String)] = []
                let simple: [(String, String)] = [
                    ("books", CKRecordType.book),
                    ("bookCategories", CKRecordType.bookCategory),
                    ("highlights", CKRecordType.highlight),
                    ("notes", CKRecordType.note),
                    ("bookmarks", CKRecordType.bookmark),
                    ("saved_words", CKRecordType.savedWord),
                    ("readingActivity", CKRecordType.readingActivity)
                ]
                // Ids are read through uuidTextSQL rather than selected raw:
                // GRDB stores UUID as a blob, and decoding that into a Swift
                // String yields mojibake or throws. Same reason the CDC
                // triggers format their recordID (migration v31).
                for (table, type) in simple {
                    let ids = try String.fetchAll(
                        db,
                        sql: "SELECT \(DatabaseManager.uuidTextSQL("id")) FROM \(table)")
                    out.append(contentsOf: ids.map { (type, $0) })
                }
                let memberships = try String.fetchAll(db, sql: """
                    SELECT \(DatabaseManager.uuidTextSQL("bookID")) || '_' ||
                           \(DatabaseManager.uuidTextSQL("categoryID"))
                    FROM bookCategoryMemberships
                    """)
                out.append(contentsOf: memberships.map {
                    (CKRecordType.bookCategoryMembership, $0)
                })
                return out
            }

            let changes = rows.map { type, localID in
                CKSyncEngine.PendingRecordZoneChange.saveRecord(
                    CKRecordName.id(type: type, localID: localID, zoneID: zoneID))
            }
            currentEngine?.state.add(pendingRecordZoneChanges: changes)
            AppLogger.log(tag: "SyncEngine", "Queued \(changes.count) records for re-upload")
        } catch {
            AppLogger.log(tag: "SyncEngine", "Re-upload enqueue failed: \(error)")
        }
    }
}
