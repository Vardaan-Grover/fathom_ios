import CloudKit
import Foundation
import GRDB
import ReadiumShared

extension Notification.Name {
    /// Posted on the main queue after remote records have been written to the
    /// local database, so screens holding loaded results can refresh.
    static let fathomSyncDidApplyRemoteChanges =
        Notification.Name("fathom.syncDidApplyRemoteChanges")
}

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

        case CKRecordType.bookCompletion:
            guard let uuid = UUID(uuidString: localID) else { return nil }
            return try BookCompletion.fetchOne(db, key: uuid)

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

        // Parents before children. Highlights, notes, bookmarks, reading
        // activity, completions and shelf memberships all carry a NOT NULL
        // foreign key to `books`, and CloudKit makes no promise about the order
        // records arrive in. Applying a child first throws an FK violation, and
        // the record is then dropped — the annotation would simply never appear
        // on that device.
        //
        // Sorting the batch fixes it whenever parent and child arrive together,
        // which is the ordinary case. A child that arrives in an earlier batch
        // than its book is still dropped; see `orphanedChildren` below.
        let ordered = modifications.sorted { lhs, rhs in
            Self.applyRank(lhs.record.recordType) < Self.applyRank(rhs.record.recordType)
        }

        // Row-backed records go in together; the singletons own their own
        // files and cannot join a database transaction.
        var rows: [CKRecord] = []
        for modification in ordered {
            let record = modification.record
            let name = record.recordID.recordName
            guard let parsed = CKRecordName.parse(name) else { continue }
            if pendingNames.contains(name) {
                noteDeferred()
                continue
            }
            if Self.isSingleton(parsed.type) {
                if await apply(record: record, cacheSystemFields: true) { noteApplied() }
            } else {
                rows.append(record)
            }
        }
        if !rows.isEmpty {
            noteApplied(await applyBatch(rows))
        }

        for deletion in deletions {
            await applyDeletion(deletion)
        }

        // A parent may have arrived in this batch, or in an earlier one during
        // a previous launch. Either way, now is when parked children can go in.
        await drainDeferred()

        // Tell the UI. View models load once and hold their results, so
        // without this a clean install pulls the whole library into SQLite and
        // shows an empty shelf until the app is relaunched — which is exactly
        // what the first clean install did.
        if !modifications.isEmpty || !deletions.isEmpty {
            await MainActor.run {
                NotificationCenter.default.post(name: .fathomSyncDidApplyRemoteChanges,
                                                object: nil)
            }
        }
    }

    /// Applies parked records whose parent has since arrived, and drops any
    /// that have waited too long.
    func drainDeferred() async {
        do {
            let parked = try await DatabaseManager.shared.dbQueue.read { db in
                try SyncDeferredApplies.pending(db: db)
            }
            guard !parked.isEmpty else { return }

            // Same single-transaction treatment as a fetched batch, and for
            // the same reason: 75 parked records used to mean 150 commits.
            // Ordering matters here too — a parked child whose parent is also
            // parked now applies in the same pass.
            let ordered = parked.sorted {
                Self.applyRank($0.recordType) < Self.applyRank($1.recordType)
            }
            let applied = (try? await DatabaseManager.shared.dbQueue.write { db -> Int in
                var count = 0
                for record in ordered {
                    guard let parsed = CKRecordName.parse(record.recordID.recordName),
                          !Self.isSingleton(parsed.type) else { continue }
                    do {
                        guard try Self.applyRow(db: db, record: record,
                                                type: parsed.type, localID: parsed.localID,
                                                cacheSystemFields: true) else { continue }
                        try SyncDeferredApplies.remove(db: db,
                                                       type: record.recordType,
                                                       recordName: record.recordID.recordName)
                        count += 1
                    } catch {
                        AppLogger.log(tag: "SyncEngine",
                                      "Deferred apply failed for \(parsed.type): \(error)")
                    }
                }
                return count
            }) ?? 0

            let pruned = try await DatabaseManager.shared.dbQueue.write { db in
                try SyncDeferredApplies.prune(db: db)
            }
            let remaining = try await DatabaseManager.shared.dbQueue.read { db in
                try SyncDeferredApplies.count(db: db)
            }

            if applied > 0 || pruned > 0 || remaining > 0 {
                AppLogger.log(tag: "SyncEngine",
                              "deferred: applied \(applied), pruned \(pruned), still waiting \(remaining)")
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Deferred drain failed: \(error)")
        }
    }

    /// Writes a merged record into the local database, and caches the change
    /// tag the retry has to present.
    ///
    /// `tagSource` is the server's copy of the record from the conflict error.
    /// Its system fields are what the next save must carry: without them the
    /// retry goes out as an insert, CloudKit answers "record to insert already
    /// exists", and the conflict repeats indefinitely.
    func applyMerged(_ record: CKRecord, cacheSystemFieldsFrom tagSource: CKRecord) async {
        await apply(record: record, cacheSystemFields: false)
        try? await DatabaseManager.shared.dbQueue.write { db in
            try SyncRecordMetadata.save(db: db, record: tagSource)
        }
    }

    /// Ordering for a fetched batch: a record type must be applied after
    /// anything it references. Lower sorts earlier.
    nonisolated static func applyRank(_ type: CKRecord.RecordType) -> Int {
        switch type {
        case CKRecordType.book, CKRecordType.bookCategory:
            return 0                    // referenced by everything below
        default:
            return 1
        }
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
    /// Applies one record in its own transaction. Used for the paths that
    /// carry a single record — a merged conflict resolution, a singleton.
    /// Batches go through `applyBatch`, which shares one transaction.
    @discardableResult
    private func apply(record: CKRecord, cacheSystemFields: Bool) async -> Bool {
        guard let parsed = CKRecordName.parse(record.recordID.recordName) else { return false }
        let (type, localID) = parsed

        if Self.isSingleton(type) {
            applySingleton(record, type: type)
            if cacheSystemFields { await cacheFields(record) }
            return true
        }

        do {
            return try await DatabaseManager.shared.dbQueue.write { db in
                try Self.applyRow(db: db, record: record, type: type, localID: localID,
                                  cacheSystemFields: cacheSystemFields)
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Apply failed for \(type)/\(localID): \(error)")
            return false
        }
    }

    /// Applies a whole batch of row-backed records in a single transaction.
    ///
    /// One transaction per record meant 309 commits on the first sync, each
    /// with its own fsync, and each one waking every `ValueObservation` in the
    /// app — the sync engine's own CDC observation and the home screen's
    /// library observation both re-ran their queries hundreds of times and
    /// delivered hundreds of reloads to the main actor. Sharing one transaction
    /// makes it one commit and one notification.
    ///
    /// It is also more correct: because the batch is ordered parents-first, a
    /// child now sees its parent's insert *within the same transaction*, so
    /// records that previously had to be parked apply immediately.
    ///
    /// - Returns: how many records were applied rather than parked.
    private func applyBatch(_ records: [CKRecord]) async -> Int {
        do {
            return try await DatabaseManager.shared.dbQueue.write { db -> Int in
                var applied = 0
                for record in records {
                    guard let parsed = CKRecordName.parse(record.recordID.recordName) else {
                        continue
                    }
                    do {
                        // Caught per record: one malformed record must not roll
                        // back the other 308.
                        if try Self.applyRow(db: db, record: record,
                                             type: parsed.type, localID: parsed.localID,
                                             cacheSystemFields: true) {
                            applied += 1
                        }
                    } catch {
                        AppLogger.log(tag: "SyncEngine",
                                      "Apply failed for \(parsed.type)/\(parsed.localID): \(error)")
                    }
                }
                return applied
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Batch apply failed: \(error)")
            return 0
        }
    }

    /// Reading position, reader settings and profile live in files, not rows.
    nonisolated static func isSingleton(_ type: CKRecord.RecordType) -> Bool {
        type == CKRecordType.readingPosition
            || type == CKRecordType.readerSettings
            || type == CKRecordType.userProfile
    }

    private func applySingleton(_ record: CKRecord, type: CKRecord.RecordType) {
        switch type {
        case CKRecordType.readingPosition: applyReadingPosition(record)
        case CKRecordType.readerSettings:  applyReaderSettings(record)
        case CKRecordType.userProfile:     applyUserProfile(record)
        default: break
        }
    }

    /// Writes one record inside an already-open transaction.
    ///
    /// - Returns: `true` if applied, `false` if parked awaiting a parent.
    nonisolated static func applyRow(db: Database,
                                     record: CKRecord,
                                     type: CKRecord.RecordType,
                                     localID: String,
                                     cacheSystemFields: Bool) throws -> Bool {
        // Every foreign key this record points at has to be present, or the
        // insert throws and the record is lost — CloudKit does not redeliver
        // it. Park it instead and retry once the parent lands.
        guard try SyncDeferredApplies.parentsExist(db: db, record: record) else {
            try SyncDeferredApplies.park(db: db, record: record)
            return false
        }

        guard try writeModel(db: db, record: record, type: type) else { return true }

        // The write above fired the CDC trigger. Clear it, or this device
        // immediately pushes back what it just pulled.
        SyncEngine.removeFromQueue(db: db, type: type, id: localID)

        if cacheSystemFields {
            try SyncRecordMetadata.save(db: db, record: record)
        }
        return true
    }

    /// Persists the model behind `record`. Returns `false` when there is
    /// nothing to write — an unknown type, or a record that will not decode.
    ///
    /// `save` rather than `upsert` throughout: GRDB's upsert emits ON CONFLICT
    /// DO UPDATE, and a statement carrying its own conflict clause overrides
    /// the conflict resolution inside any trigger it fires — which turns the
    /// CDC trigger's `INSERT OR REPLACE INTO cloudkit_pending_changes` into a
    /// plain INSERT and makes it fail whenever a change is already queued for
    /// that record. `save` is UPDATE-then-INSERT with no conflict clause.
    // swiftlint:disable:next cyclomatic_complexity
    private nonisolated static func writeModel(db: Database,
                                               record: CKRecord,
                                               type: CKRecord.RecordType) throws -> Bool {
        switch type {

        case CKRecordType.book:
            guard let incoming = Book.from(ckRecord: record) else { return false }
            if let existing = try Book.fetchOne(db, key: incoming.id) {
                var merged = incoming
                // Fields that describe this device's copy of the file are never
                // carried on the record — keep the local values rather than
                // resetting them. (§3.2)
                merged.preprocessingStatus = existing.preprocessingStatus
                merged.aiAnalysisProgress  = existing.aiAnalysisProgress
                merged.aiEnabled           = existing.aiEnabled
                merged.backendBookID       = existing.backendBookID
                try merged.update(db)
            } else {
                try incoming.insert(db, onConflict: .ignore)
            }

        case CKRecordType.bookCompletion:
            guard let incoming = BookCompletion.from(ckRecord: record) else { return false }
            try incoming.save(db)

        case CKRecordType.bookCategory:
            guard let incoming = BookCategory.from(ckRecord: record) else { return false }
            try incoming.save(db)

        case CKRecordType.bookCategoryMembership:
            guard let incoming = BookCategoryMembership.from(ckRecord: record) else { return false }
            try incoming.save(db)

        case CKRecordType.highlight:
            guard let incoming = Highlight.from(ckRecord: record) else { return false }
            try incoming.save(db)

        case CKRecordType.note:
            guard let incoming = Note.from(ckRecord: record) else { return false }
            try incoming.save(db)

        case CKRecordType.bookmark:
            guard let incoming = Bookmark.from(ckRecord: record) else { return false }
            try incoming.save(db)

        case CKRecordType.savedWord:
            guard let incoming = SavedWord.from(ckRecord: record) else { return false }
            try incoming.save(db)

        case CKRecordType.readingActivity:
            guard let incoming = ReadingActivity.from(ckRecord: record) else { return false }
            try incoming.save(db)

        default:
            return false
        }
        return true
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
                case CKRecordType.bookCompletion:
                    if let uuid = UUID(uuidString: localID) {
                        _ = try BookCompletion.deleteOne(db, key: uuid)
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
                // (table, key column, record type). bookCompletions is keyed
                // on the book it belongs to, not on an id of its own.
                let simple: [(String, String, String)] = [
                    ("books", "id", CKRecordType.book),
                    ("bookCompletions", "bookID", CKRecordType.bookCompletion),
                    ("bookCategories", "id", CKRecordType.bookCategory),
                    ("highlights", "id", CKRecordType.highlight),
                    ("notes", "id", CKRecordType.note),
                    ("bookmarks", "id", CKRecordType.bookmark),
                    ("saved_words", "id", CKRecordType.savedWord),
                    ("readingActivity", "id", CKRecordType.readingActivity)
                ]
                // Ids are read through uuidTextSQL rather than selected raw:
                // GRDB stores UUID as a blob, and decoding that into a Swift
                // String yields mojibake or throws. Same reason the CDC
                // triggers format their recordID (migration v31).
                for (table, keyColumn, type) in simple {
                    let ids = try String.fetchAll(
                        db,
                        sql: "SELECT \(DatabaseManager.uuidTextSQL(keyColumn)) FROM \(table)")
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
