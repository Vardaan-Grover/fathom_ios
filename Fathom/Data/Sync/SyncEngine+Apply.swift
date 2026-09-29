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
    /// row no longer exists locally (the pending save is then dropped).
    func recordToSave(_ recordID: CKRecord.ID) async -> CKRecord? {
        let record = await localRecord(recordID, seedFromCache: true)
        if record == nil {
            currentEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        }
        return record
    }

    /// The record describing this device's current state for `recordID`.
    ///
    /// - Parameter seedFromCache: build on the last record the server
    ///   acknowledged, so the save carries its change tag and CloudKit can
    ///   report a real ancestor if it conflicts. Pass `false` for a record
    ///   that is only compared, never saved.
    func localRecord(_ recordID: CKRecord.ID, seedFromCache: Bool) async -> CKRecord? {
        guard let parsed = CKRecordName.parse(recordID.recordName) else { return nil }
        let (type, localID) = parsed

        // Singletons live in file-backed stores, not SQLite.
        switch type {
        case CKRecordType.readingPosition:
            return await positionRecord(recordID, localID: localID, seedFromCache: seedFromCache)
        case CKRecordType.readerSettings:
            return await settingsRecord(recordID, seedFromCache: seedFromCache)
        case CKRecordType.userProfile:
            return await profileRecord(recordID, seedFromCache: seedFromCache)
        default:
            break
        }

        return try? await DatabaseManager.shared.dbQueue.read { db in
            guard let syncable = try Self.localModel(db: db, type: type, localID: localID) else {
                return nil
            }
            let record = try seedFromCache
                ? Self.seededRecord(db: db, type: type, recordID: recordID)
                : CKRecord(recordType: type, recordID: recordID)
            syncable.apply(to: record)
            return record
        }
    }

    /// The last record the server acknowledged, or a fresh one when the
    /// server has never seen it.
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

    private func seed(_ recordID: CKRecord.ID, type: CKRecord.RecordType, fromCache: Bool) async -> CKRecord {
        guard fromCache else { return CKRecord(recordType: type, recordID: recordID) }
        return (try? await DatabaseManager.shared.dbQueue.read { db in
            try Self.seededRecord(db: db, type: type, recordID: recordID)
        }) ?? CKRecord(recordType: type, recordID: recordID)
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

    private func positionRecord(_ recordID: CKRecord.ID, localID: String,
                                seedFromCache: Bool) async -> CKRecord? {
        guard let bookID = UUID(uuidString: localID),
              let state = ReadingStateStore.shared.state(forBookID: bookID)
        else { return nil }

        let record = await seed(recordID, type: CKRecordType.readingPosition, fromCache: seedFromCache)
        ReadingPositionRecord.write(state, bookID: bookID, into: record)
        return record
    }

    private func settingsRecord(_ recordID: CKRecord.ID, seedFromCache: Bool) async -> CKRecord? {
        let settings = ReaderSettingsStore.shared.load()
        guard let data = try? JSONEncoder().encode(settings) else { return nil }

        let record = await seed(recordID, type: CKRecordType.readerSettings, fromCache: seedFromCache)
        record["settingsJSON"] = data
        record["modifiedAt"] = ReaderSettingsStore.shared.modifiedAt ?? Date()
        return record
    }

    private func profileRecord(_ recordID: CKRecord.ID, seedFromCache: Bool) async -> CKRecord? {
        let profile = UserProfileStore.shared.load()

        let record = await seed(recordID, type: CKRecordType.userProfile, fromCache: seedFromCache)
        record["displayName"] = profile.displayName
        record["avatarEmoji"] = profile.avatarEmoji
        record["avatarColorHex"] = profile.avatarColorHex
        record["modifiedAt"] = UserProfileStore.shared.modifiedAt ?? Date()
        return record
    }
}

// MARK: - Applying fetched changes

extension SyncEngine {

    /// Writes fetched changes into the local store.
    ///
    /// - Returns: how many changes actually altered local data — not counting
    ///   echoes of this device's own saves or records deferred for a merge.
    @discardableResult
    func applyFetched(modifications: [CKDatabase.RecordZoneChange.Modification],
                      deletions: [CKDatabase.RecordZoneChange.Deletion]) async -> Int {

        // Records with an unsent local change are deliberately left alone.
        //
        // Writing the server's version over an edit that has not been pushed
        // yet would lose it: once locally, and again when the pending push
        // rebuilds its record from the database it just overwrote. Skipping
        // the write *and* the cache means the push still goes out carrying the
        // old change tag, CloudKit answers `serverRecordChanged`, and the merge
        // runs with both versions in hand. This snapshot covers changes the
        // engine already holds; `applyBatch` also checks the queue table inside
        // its transaction, for edits the engine has not been told about yet.
        let pendingNames = pendingRecordNames()

        // Parents before children: highlights, notes, bookmarks, reading
        // activity, completions and memberships carry foreign keys to `books`
        // (and memberships to `bookCategories`), and CloudKit makes no promise
        // about arrival order. A child that arrives in an earlier batch than
        // its parent is parked — see `SyncDeferredApplies`.
        let ordered = modifications.sorted { lhs, rhs in
            Self.applyRank(lhs.record.recordType) < Self.applyRank(rhs.record.recordType)
        }

        var applied = 0
        var skipped = 0
        var rows: [CKRecord] = []
        for modification in ordered {
            let record = modification.record
            let name = record.recordID.recordName
            guard let parsed = CKRecordName.parse(name) else { continue }
            if pendingNames.contains(name) {
                skipped += 1
                continue
            }
            if Self.isSingleton(parsed.type) {
                if await applyFetchedSingleton(record) { applied += 1 }
            } else {
                rows.append(record)
            }
        }
        if !rows.isEmpty {
            let outcome = await applyBatch(rows)
            applied += outcome.applied
            skipped += outcome.skipped
        }

        for deletion in deletions {
            // Not a `where` clause: it cannot contain `await`.
            let changed = await applyRemoteDeletion(deletion.recordID)
            if changed { applied += 1 }
        }

        // A parent may have arrived in this batch, or in an earlier one during
        // a previous launch. Either way, now is when parked children can go in.
        applied += await drainDeferred()

        noteApplied(applied)
        if skipped > 0 { noteDeferred(skipped) }

        // Tell the UI. View models load once and hold their results.
        if applied > 0 {
            await postRemoteChangeNotification()
        }
        return applied
    }

    func postRemoteChangeNotification() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .fathomSyncDidApplyRemoteChanges, object: nil)
        }
    }

    /// Record names with a pending save *or* delete in the engine.
    private func pendingRecordNames() -> Set<String> {
        guard let engine = currentEngine else { return [] }
        var names = Set<String>()
        for change in engine.state.pendingRecordZoneChanges {
            switch change {
            case .saveRecord(let id): names.insert(id.recordName)
            case .deleteRecord(let id): names.insert(id.recordName)
            @unknown default: break
            }
        }
        return names
    }

    nonisolated private struct BatchOutcome: Sendable {
        var applied = 0
        var skipped = 0
    }

    /// Applies a whole batch of row-backed records in a single transaction:
    /// one commit and one round of observation callbacks instead of one per
    /// record, and a child sees its parent's insert from earlier in the batch.
    private func applyBatch(_ records: [CKRecord]) async -> BatchOutcome {
        do {
            return try await DatabaseManager.shared.dbQueue.write { db -> BatchOutcome in
                var outcome = BatchOutcome()
                for record in records {
                    guard let parsed = CKRecordName.parse(record.recordID.recordName) else {
                        continue
                    }
                    // A local edit queued but not yet handed to the engine.
                    if try Self.hasQueuedLocalChange(db: db, type: parsed.type, localID: parsed.localID) {
                        outcome.skipped += 1
                        continue
                    }
                    // This device's own save coming back round. Already applied.
                    if try Self.isEcho(db: db, record: record, type: parsed.type) {
                        continue
                    }
                    do {
                        // One savepoint per record: a record that fails must not
                        // roll back the rest of the batch, nor leave half of
                        // itself written.
                        var didApply = false
                        try db.inSavepoint {
                            didApply = try Self.applyRow(db: db, record: record,
                                                         type: parsed.type, localID: parsed.localID,
                                                         cacheSystemFields: true)
                            return .commit
                        }
                        if didApply { outcome.applied += 1 }
                    } catch {
                        // CloudKit will not deliver this record again, so park it
                        // rather than drop it: it is retried on every drain.
                        AppLogger.log(tag: "SyncEngine",
                                      "Apply failed for \(parsed.type)/\(parsed.localID), parking: \(error)")
                        try? SyncDeferredApplies.park(db: db, record: record)
                    }
                }
                return outcome
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Batch apply failed: \(error)")
            return BatchOutcome()
        }
    }

    nonisolated private static func hasQueuedLocalChange(db: Database, type: String, localID: String) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS (SELECT 1 FROM cloudkit_pending_changes
                           WHERE recordType = ? AND recordID = ?)
            """, arguments: [type, localID]) ?? false
    }

    /// Whether `record` is the version this device already holds — typically
    /// its own save, fetched back. Re-applying it would rewrite the row, wake
    /// every observer and reload the UI for nothing.
    nonisolated private static func isEcho(db: Database, record: CKRecord, type: String) throws -> Bool {
        guard let tag = record.recordChangeTag,
              let cached = try SyncRecordMetadata.lastKnownRecord(db: db, type: type,
                                                                  recordName: record.recordID.recordName)
        else { return false }
        return cached.recordChangeTag == tag
    }

    private func applyFetchedSingleton(_ record: CKRecord) async -> Bool {
        let isEcho = (try? await DatabaseManager.shared.dbQueue.read { db in
            try Self.isEcho(db: db, record: record, type: record.recordType)
        }) ?? false
        guard !isEcho else { return false }
        return await apply(record: record, cacheSystemFields: true)
    }

    /// Applies parked records whose parent has since arrived, and drops any
    /// that have waited too long.
    ///
    /// - Returns: how many parked records were applied.
    @discardableResult
    func drainDeferred() async -> Int {
        do {
            let parked = try await DatabaseManager.shared.dbQueue.read { db in
                try SyncDeferredApplies.pending(db: db)
            }
            guard !parked.isEmpty else { return 0 }

            // Ordered so a parked child whose parent is also parked applies in
            // the same pass.
            let ordered = parked.sorted {
                Self.applyRank($0.recordType) < Self.applyRank($1.recordType)
            }
            let applied = try await DatabaseManager.shared.dbQueue.write { db -> Int in
                var count = 0
                for record in ordered {
                    guard let parsed = CKRecordName.parse(record.recordID.recordName),
                          !Self.isSingleton(parsed.type) else { continue }
                    // Still waiting: leave it be. Re-parking here used to
                    // rewrite every waiting row on every drain.
                    guard try SyncDeferredApplies.parentsExist(db: db, record: record) else { continue }
                    do {
                        var didApply = false
                        try db.inSavepoint {
                            didApply = try Self.applyRow(db: db, record: record,
                                                         type: parsed.type, localID: parsed.localID,
                                                         cacheSystemFields: true)
                            return .commit
                        }
                        if didApply { count += 1 }
                    } catch {
                        AppLogger.log(tag: "SyncEngine",
                                      "Deferred apply failed for \(parsed.type): \(error)")
                    }
                }
                return count
            }

            let pruned = try await DatabaseManager.shared.dbQueue.write { db in
                try SyncDeferredApplies.prune(db: db)
            }
            let remaining = try await DatabaseManager.shared.dbQueue.read { db in
                try SyncDeferredApplies.count(db: db)
            }

            if applied > 0 || pruned > 0 {
                AppLogger.log(tag: "SyncEngine",
                              "deferred: applied \(applied), pruned \(pruned), still waiting \(remaining)")
            }
            return applied
        } catch {
            AppLogger.log(tag: "SyncEngine", "Deferred drain failed: \(error)")
            return 0
        }
    }

    // MARK: - Conflicts

    /// Resolves a `serverRecordChanged` conflict and writes the result locally.
    ///
    /// Three inputs, and each matters:
    /// - **client** is this device's state *now*, read fresh — not the record
    ///   that was sent. An edit made while the conflicting push was in flight
    ///   used to be overwritten by a merge of the older, sent version.
    /// - **server** is what CloudKit holds.
    /// - **ancestor** is the version both diverged from: CloudKit's
    ///   `ancestorRecord`, or the cached copy it was derived from.
    ///
    /// Afterwards the server's (unmerged) record is cached, so the retry is
    /// built on its change tag and — if it conflicts again — has it as the
    /// ancestor.
    func resolveConflict(recordID: CKRecord.ID, server: CKRecord, reportedAncestor: CKRecord?) async {
        guard let parsed = CKRecordName.parse(recordID.recordName) else { return }

        var ancestor: CKRecord?
        if let reportedAncestor, !reportedAncestor.allKeys().isEmpty {
            ancestor = reportedAncestor
        } else {
            let cached: CKRecord? = (try? await DatabaseManager.shared.dbQueue.read { db in
                try SyncRecordMetadata.lastKnownRecord(db: db, type: parsed.type,
                                                       recordName: recordID.recordName)
            }) ?? nil
            if let cached, !cached.allKeys().isEmpty { ancestor = cached }
        }

        if let client = await localRecord(recordID, seedFromCache: false) {
            let merged = SyncMerge.resolve(client: client, server: server, ancestor: ancestor)
            await apply(record: merged, cacheSystemFields: false)
        }
        // With no local row the record was deleted here since the push began;
        // the pending delete follows, and needs the server's current tag.
        await cacheFields(server)
    }

    // MARK: - Applying one record

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

    /// Applies one record in its own transaction — a merged conflict
    /// resolution or a singleton. Batches go through `applyBatch`.
    @discardableResult
    private func apply(record: CKRecord, cacheSystemFields: Bool) async -> Bool {
        guard let parsed = CKRecordName.parse(record.recordID.recordName) else { return false }
        let (type, localID) = parsed

        if Self.isSingleton(type) {
            let changed = applySingleton(record, type: type)
            if cacheSystemFields { await cacheFields(record) }
            return changed
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

    /// Reading position, reader settings and profile live in files, not rows.
    nonisolated static func isSingleton(_ type: CKRecord.RecordType) -> Bool {
        type == CKRecordType.readingPosition
            || type == CKRecordType.readerSettings
            || type == CKRecordType.userProfile
    }

    /// - Returns: whether local state changed.
    private func applySingleton(_ record: CKRecord, type: CKRecord.RecordType) -> Bool {
        switch type {
        case CKRecordType.readingPosition: return applyReadingPosition(record)
        case CKRecordType.readerSettings:  return applyReaderSettings(record)
        case CKRecordType.userProfile:     return applyUserProfile(record)
        default:                           return false
        }
    }

    /// Writes one record inside an already-open write transaction, with the
    /// sync triggers suppressed — a pulled record is not a local change, and
    /// must neither be queued for push nor have its `modifiedAt` restamped.
    ///
    /// - Returns: `true` if applied, `false` if parked for a later attempt.
    nonisolated static func applyRow(db: Database,
                                     record: CKRecord,
                                     type: CKRecord.RecordType,
                                     localID: String,
                                     cacheSystemFields: Bool) throws -> Bool {
        try SyncApplyContext.perform(db) {
            // Every foreign key this record points at has to be present, or the
            // insert throws and the record is lost — CloudKit does not redeliver
            // it. Park it instead and retry once the parent lands.
            guard try SyncDeferredApplies.parentsExist(db: db, record: record) else {
                try SyncDeferredApplies.park(db: db, record: record)
                return false
            }

            guard try Self.writeModel(db: db, record: record, type: type) else {
                // Missing a field this build requires — perhaps written by a
                // newer version of the app. Counting it as applied would lose
                // it for good; parked, it is retried until it ages out.
                AppLogger.log(tag: "SyncEngine",
                              "Could not decode \(type)/\(localID) — parking it")
                try SyncDeferredApplies.park(db: db, record: record)
                return false
            }

            // Any older copy of this record parked earlier is now stale; left
            // in place, the next drain would apply it over this newer version.
            let name = record.recordID.recordName
            if try SyncDeferredApplies.contains(db: db, type: type, recordName: name) {
                try SyncDeferredApplies.remove(db: db, type: type, recordName: name)
            }

            if cacheSystemFields {
                try SyncRecordMetadata.save(db: db, record: record)
            }
            return true
        }
    }

    /// Persists the model behind `record`. Returns `false` when there is
    /// nothing to write — an unknown type, or a record that will not decode.
    ///
    /// `save` rather than `upsert` throughout: GRDB's upsert emits ON CONFLICT
    /// DO UPDATE, and a statement carrying its own conflict clause overrides
    /// the conflict resolution inside any trigger it fires. The sync triggers
    /// are suppressed during apply, but the rule is kept so this code stays
    /// safe if that ever changes.
    private nonisolated static func writeModel( // swiftlint:disable:this cyclomatic_complexity
                                               db: Database,
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
                try incoming.insert(db)
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

    func cacheFields(_ record: CKRecord) async {
        try? await DatabaseManager.shared.dbQueue.write { db in
            try SyncRecordMetadata.save(db: db, record: record)
        }
    }

    // MARK: - Singleton apply

    private func applyReadingPosition(_ record: CKRecord) -> Bool {
        guard let (bookID, state) = ReadingPositionRecord.read(record) else { return false }

        // Position and furthest progress resolve independently — the store
        // owns that decision so it happens atomically with the write. An older
        // remote position loses, but the progress it carries can still raise
        // the high-water mark. See §3.6.
        return ReadingStateStore.shared.applyRemoteState(
            locatorJSON: state.locatorJSON,
            savedAt: state.savedAt,
            furthestProgression: state.furthestProgression,
            forBookID: bookID)
    }

    private func applyReaderSettings(_ record: CKRecord) -> Bool {
        guard
            let data = record["settingsJSON"] as? Data,
            let incoming = try? JSONDecoder().decode(ReaderSettings.self, from: data),
            let modifiedAt = record["modifiedAt"] as? Date
        else { return false }

        if let local = ReaderSettingsStore.shared.modifiedAt, modifiedAt <= local { return false }
        ReaderSettingsStore.shared.applyRemote(incoming, modifiedAt: modifiedAt)
        return true
    }

    private func applyUserProfile(_ record: CKRecord) -> Bool {
        guard let modifiedAt = record["modifiedAt"] as? Date else { return false }
        if let local = UserProfileStore.shared.modifiedAt, modifiedAt <= local { return false }

        var profile = UserProfileStore.shared.load()
        profile.displayName = record["displayName"] as? String
        profile.avatarEmoji = record["avatarEmoji"] as? String
        if let hex = record["avatarColorHex"] as? String { profile.avatarColorHex = hex }
        UserProfileStore.shared.applyRemote(profile, modifiedAt: modifiedAt)
        return true
    }

    // MARK: - Deletions

    /// Applies a deletion that happened on another device.
    ///
    /// A remote delete wins over a local edit still queued for the same
    /// record: the record is gone everywhere else, and pushing the edit would
    /// only bring it back.
    ///
    /// - Returns: whether local data changed.
    @discardableResult
    func applyRemoteDeletion(_ recordID: CKRecord.ID) async -> Bool {
        guard let parsed = CKRecordName.parse(recordID.recordName) else { return false }
        let (type, localID) = parsed
        let name = recordID.recordName

        switch type {
        case CKRecordType.readingPosition:
            if let bookID = UUID(uuidString: localID) {
                ReadingStateStore.shared.removeState(forBookID: bookID, notifySync: false)
            }
            await forgetCachedRecord(type: type, recordName: name)
            return true

        case CKRecordType.readerSettings, CKRecordType.userProfile:
            // Only ever removed with the whole zone. The local copy stays.
            await forgetCachedRecord(type: type, recordName: name)
            return false

        default:
            break
        }

        do {
            let (deleted, files) = try await DatabaseManager.shared.dbQueue.write { db -> (Bool, [BookFileRef]) in
                try SyncApplyContext.perform(db) {
                    // Read before deleting: the row is the only record of
                    // which files were the book's.
                    let files: [BookFileRef] = try type == CKRecordType.book
                        ? Self.fileRefs(forBookID: localID, db: db)
                        : []
                    let changed = try Self.deleteRow(db: db, type: type, localID: localID)
                    SyncEngine.removeFromQueue(db: db, type: type, id: localID)
                    try SyncRecordMetadata.delete(db: db, type: type, recordName: name)
                    try SyncDeferredApplies.remove(db: db, type: type, recordName: name)
                    return (changed, files)
                }
            }
            if type == CKRecordType.book, let bookID = UUID(uuidString: localID) {
                ReadingStateStore.shared.removeState(forBookID: bookID, notifySync: false)
                // The deleting device removed the iCloud copies; this removes
                // ours (and any iCloud copy it could not).
                ICloudFileStore.shared.delete(files)
            }
            return deleted
        } catch {
            AppLogger.log(tag: "SyncEngine", "Delete apply failed for \(type)/\(localID): \(error)")
            return false
        }
    }

    /// Deletes the row behind a record. Deleting a book or shelf cascades to
    /// its children through the foreign keys; with the apply context raised,
    /// those cascades queue nothing — the deleting device pushes them.
    nonisolated private static func deleteRow(db: Database, type: String, localID: String) throws -> Bool {
        switch type {
        case CKRecordType.bookCategoryMembership:
            guard let parts = CKRecordName.parseMembership(localID: localID) else { return false }
            return try BookCategoryMembership
                .filter(Column("bookID") == parts.bookID && Column("categoryID") == parts.categoryID)
                .deleteAll(db) > 0
        default:
            break
        }

        guard let uuid = UUID(uuidString: localID) else { return false }
        switch type {
        case CKRecordType.book:            return try Book.deleteOne(db, key: uuid)
        case CKRecordType.bookCompletion:  return try BookCompletion.deleteOne(db, key: uuid)
        case CKRecordType.bookCategory:    return try BookCategory.deleteOne(db, key: uuid)
        case CKRecordType.highlight:       return try Highlight.deleteOne(db, key: uuid)
        case CKRecordType.note:            return try Note.deleteOne(db, key: uuid)
        case CKRecordType.bookmark:        return try Bookmark.deleteOne(db, key: uuid)
        case CKRecordType.savedWord:       return try SavedWord.deleteOne(db, key: uuid)
        case CKRecordType.readingActivity: return try ReadingActivity.deleteOne(db, key: uuid)
        default:                           return false
        }
    }

    /// The files a book row points at, including its reflection image.
    nonisolated private static func fileRefs(forBookID localID: String, db: Database) throws -> [BookFileRef] {
        guard let uuid = UUID(uuidString: localID),
              let book = try Book.fetchOne(db, key: uuid) else { return [] }
        var refs: [BookFileRef] = []
        if let name = book.localFilename { refs.append(BookFileRef(kind: .book, filename: name)) }
        if let name = book.coverFilename { refs.append(BookFileRef(kind: .cover, filename: name)) }
        if let name = try BookCompletion.fetchOne(db, key: uuid)?.reflectionImageFilename {
            refs.append(BookFileRef(kind: .reflection, filename: name))
        }
        return refs
    }

    private func forgetCachedRecord(type: String, recordName: String) async {
        try? await DatabaseManager.shared.dbQueue.write { db in
            try SyncRecordMetadata.delete(db: db, type: type, recordName: recordName)
        }
    }

    // MARK: - Full upload

    /// Queues every local record for push — rows and singletons. Used after a
    /// sign-in and when the zone has been recreated with nothing in it.
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
                // GRDB stores UUID as a blob (see migration v31).
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

            // Reading positions, settings and profile have no rows to select.
            // Leaving them out meant a zone reset or a new account got the
            // library without anyone's place in it.
            let singletons = await singletonCandidates()

            let changes = (rows + singletons).map { type, localID in
                CKSyncEngine.PendingRecordZoneChange.saveRecord(
                    CKRecordName.id(type: type, localID: localID, zoneID: zoneID))
            }
            currentEngine?.state.add(pendingRecordZoneChanges: changes)
            AppLogger.log(tag: "SyncEngine", "Queued \(changes.count) records for upload")
        } catch {
            AppLogger.log(tag: "SyncEngine", "Upload enqueue failed: \(error)")
        }
    }
}
