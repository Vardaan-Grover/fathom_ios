import CloudKit
import Foundation
import GRDB

// MARK: - Pending change row (mirrors cloudkit_pending_changes)

nonisolated struct PendingChangeRow: Decodable, FetchableRecord {
    let recordType: String
    let recordID: String
    let operation: String   // "upsert" | "delete"
    /// Raw column text rather than a Date: cleanup compares against the exact
    /// stored string, and round-tripping through Date changes the format.
    let queuedAt: String
}

// MARK: - SyncEngine

/// Drives CloudKit sync for the private database.
///
/// Change *detection* is still the SQLite triggers that write into
/// `cloudkit_pending_changes` — they catch every local mutation without any
/// call site having to remember to announce it, which is worth keeping.
/// Change *transport* is `CKSyncEngine`, which owns the parts the previous
/// hand-rolled engine did not implement at all: server change tokens, batching
/// under the 400-record limit, exponential backoff, request throttling,
/// account changes, zone deletion, and retry after `changeTokenExpired`.
///
/// Conflicts are resolved by `SyncMerge` against the ancestor record, per
/// `docs/sync-conflict-policy.md`.
actor SyncEngine: CKSyncEngineDelegate {

    static let shared = SyncEngine()
    private init() {}

    // MARK: Configuration

    private static let containerID = "iCloud.com.Vardaan.Fathom"

    /// One fixed zone. The private database is already scoped to the signed-in
    /// Apple ID, so a single well-known zone name is all every device of the
    /// same user needs to converge.
    static let zoneName = "FathomZone"

    nonisolated var container: CKContainer { CKContainer(identifier: Self.containerID) }
    nonisolated var database: CKDatabase { container.privateCloudDatabase }

    nonisolated var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: State

    private var engine: CKSyncEngine?
    /// Read-only access for the apply extension.
    var currentEngine: CKSyncEngine? { engine }
    private var cdcObserver: AnyDatabaseCancellable?
    private var notificationTokens: [NSObjectProtocol] = []

    /// The queue timestamp each record carried when it was handed to the sync
    /// engine. On a successful send only rows at or before this timestamp are
    /// cleared, so an edit made *while* the push was in flight survives and is
    /// pushed again. Erring toward a redundant push is correct; erring toward a
    /// dropped change is not.
    private var enqueuedAt: [String: String] = [:]

    /// Tallies for one fetch/send cycle, logged as a single summary line.
    ///
    /// Successful applies used to produce no output at all, which meant the
    /// only visible sync activity was its failures — a run that worked and a
    /// run that did nothing looked identical in the log. That is no way to
    /// verify a system whose whole job is to move records quietly.
    private struct Tally {
        var fetched = 0, applied = 0, deferred = 0, deleted = 0
        var sent = 0, sentDeletes = 0, conflicts = 0, failed = 0
        var isEmpty: Bool {
            fetched == 0 && applied == 0 && deferred == 0 && deleted == 0
                && sent == 0 && sentDeletes == 0 && conflicts == 0 && failed == 0
        }
    }
    private var tally = Tally()

    func noteApplied(_ count: Int = 1) { tally.applied += count }
    func noteDeferred() { tally.deferred += 1 }

    // MARK: - Lifecycle

    /// Call once after `ICloudFileStore.configure()` reports iCloud available.
    func start() async {
        guard engine == nil else { return }

        let restored = SyncStateStore.load()

        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: restored,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        // First launch on this device: ask for the zone. CKSyncEngine creates
        // it before sending any record change that needs it, and retries on
        // its own if the request fails.
        if restored == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }

        await enqueuePendingChanges()
        startCDCObservation()
        startNotificationObservers()

        AppLogger.log(tag: "SyncEngine", "Started (zone \(Self.zoneName))")

        // Pull whatever changed while this device was not running.
        //
        // The foreground hook in FathomApp cannot do this on a cold launch:
        // `scenePhase` reaches `.active` long before SyncBootstrap has resolved
        // the iCloud container, run the file migration and got here, so that
        // call arrives while `engine` is still nil and is dropped. Without this
        // line a cold launch never fetches at all — which is why every early
        // run reported `fetched 0` while records sat waiting in the zone.
        // Parents may have arrived in an earlier session, so drain before the
        // fetch as well as after it.
        await drainDeferred()

        await fetchChangesIfNeeded()

        // An empty cycle logs nothing, so without this a startup fetch that
        // found no changes is indistinguishable from one that never ran — the
        // exact ambiguity that made the missing fetch hard to spot. Seeing this
        // line with no `cycle:` line after it means "fetched, nothing waiting".
        AppLogger.log(tag: "SyncEngine", "startup fetch complete")
    }

    func stop() {
        cdcObserver?.cancel()
        cdcObserver = nil
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens = []
        engine = nil
        enqueuedAt = [:]
        AppLogger.log(tag: "SyncEngine", "Stopped")
    }

    /// Foreground refresh. CKSyncEngine also syncs on its own schedule; this
    /// makes a returning user's first screen current without waiting for it.
    func fetchChangesIfNeeded() async {
        guard let engine else {
            // Expected once per cold launch: scenePhase reaches .active before
            // SyncBootstrap has started the engine. Harmless, because start()
            // fetches itself — but worth seeing, because a silent return here
            // is what hid the missing startup fetch for four rounds.
            AppLogger.log(tag: "SyncEngine", "foreground fetch beat startup — start() will cover it")
            return
        }
        do {
            try await engine.fetchChanges()
        } catch {
            AppLogger.log(tag: "SyncEngine", "Manual fetch failed: \(error)")
        }
    }

    // MARK: - Local change detection

    private func startCDCObservation() {
        let observation = ValueObservation.tracking { db -> [PendingChangeRow] in
            try PendingChangeRow.fetchAll(db, sql: """
                SELECT recordType, recordID, operation, queuedAt
                FROM   cloudkit_pending_changes
                ORDER  BY queuedAt ASC
                """)
        }

        cdcObserver = observation.start(
            in: DatabaseManager.shared.dbQueue,
            scheduling: .async(onQueue: .global(qos: .utility)),
            onError: { error in
                AppLogger.log(tag: "SyncEngine", "CDC observation error: \(error)")
            },
            onChange: { [weak self] rows in
                guard !rows.isEmpty else { return }
                Task { await self?.enqueue(rows) }
            }
        )
    }

    private func enqueuePendingChanges() async {
        do {
            let rows = try await DatabaseManager.shared.dbQueue.read { db in
                try PendingChangeRow.fetchAll(db, sql: """
                    SELECT recordType, recordID, operation, queuedAt
                    FROM   cloudkit_pending_changes
                    ORDER  BY queuedAt ASC
                    """)
            }
            enqueue(rows)
        } catch {
            AppLogger.log(tag: "SyncEngine", "Failed to read pending changes: \(error)")
        }
    }

    private func enqueue(_ rows: [PendingChangeRow]) {
        guard let engine else { return }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for row in rows {
            // AIConversation rows can still exist from builds predating v26.
            guard CKRecordType.all.contains(row.recordType) else { continue }

            let name = CKRecordName.make(type: row.recordType, localID: row.recordID)
            let id = CKRecord.ID(recordName: name, zoneID: zoneID)
            enqueuedAt[name] = row.queuedAt
            changes.append(row.operation == "delete" ? .deleteRecord(id) : .saveRecord(id))
        }

        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        AppLogger.log(tag: "SyncEngine", "queued \(changes.count) local change(s) to push")
    }

    /// Queues a record that has no CDC trigger behind it — the three singletons
    /// that live in file-backed stores rather than SQLite tables.
    private func enqueueSingleton(type: CKRecord.RecordType, localID: String) {
        guard let engine else { return }
        let id = CKRecordName.id(type: type, localID: localID, zoneID: zoneID)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    private func startNotificationObservers() {
        let center = NotificationCenter.default

        notificationTokens.append(center.addObserver(
            forName: ReadingStateStore.didSaveNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let bookID = note.userInfo?["bookID"] as? UUID else { return }
            Task { await self?.enqueueSingleton(type: CKRecordType.readingPosition,
                                                localID: bookID.uuidString) }
        })

        notificationTokens.append(center.addObserver(
            forName: ReaderSettingsStore.didSaveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.enqueueSingleton(type: CKRecordType.readerSettings,
                                                localID: "current") }
        })

        notificationTokens.append(center.addObserver(
            forName: UserProfileStore.didSaveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.enqueueSingleton(type: CKRecordType.userProfile,
                                                localID: "current") }
        })
    }

    // MARK: - CKSyncEngineDelegate

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {

        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.recordToSave(recordID)
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {

        case .stateUpdate(let e):
            SyncStateStore.save(e.stateSerialization)

        case .accountChange(let e):
            await handleAccountChange(e)

        case .fetchedRecordZoneChanges(let e):
            tally.fetched += e.modifications.count
            tally.deleted += e.deletions.count
            await applyFetched(modifications: e.modifications, deletions: e.deletions)

        case .fetchedDatabaseChanges(let e):
            await handleDatabaseChanges(e)

        case .sentRecordZoneChanges(let e):
            tally.sent += e.savedRecords.count
            tally.sentDeletes += e.deletedRecordIDs.count
            tally.failed += e.failedRecordSaves.count + e.failedRecordDeletes.count
            await handleSentChanges(e, syncEngine: syncEngine)

        case .sentDatabaseChanges(let e):
            for failure in e.failedZoneSaves {
                AppLogger.log(tag: "SyncEngine",
                              "Zone save failed \(failure.zone.zoneID.zoneName): \(failure.error)")
            }

        case .didFetchChanges, .didSendChanges:
            flushTally()

        case .willFetchChanges, .willSendChanges, .willFetchRecordZoneChanges:
            break

        case .didFetchRecordZoneChanges(let e):
            if let error = e.error {
                AppLogger.log(tag: "SyncEngine",
                              "Zone fetch error \(e.zoneID.zoneName): \(error)")
            }

        @unknown default:
            AppLogger.log(tag: "SyncEngine", "Unhandled sync event: \(event)")
        }
    }

    // MARK: - Sent changes

    private func handleSentChanges(_ e: CKSyncEngine.Event.SentRecordZoneChanges,
                                   syncEngine: CKSyncEngine) async {

        // Successful saves: cache the server's system fields so the next push
        // carries a change tag, and clear the CDC rows they came from.
        if !e.savedRecords.isEmpty || !e.deletedRecordIDs.isEmpty {
            let saved = e.savedRecords
            let deleted = e.deletedRecordIDs
            let watermarks = enqueuedAt
            do {
                try await DatabaseManager.shared.dbQueue.write { db in
                    for record in saved {
                        try SyncRecordMetadata.save(db: db, record: record)
                        Self.clearQueueRow(db: db,
                                           recordName: record.recordID.recordName,
                                           upTo: watermarks[record.recordID.recordName])
                    }
                    for id in deleted {
                        if let parsed = CKRecordName.parse(id.recordName) {
                            try SyncRecordMetadata.delete(db: db,
                                                          type: parsed.type,
                                                          recordName: id.recordName)
                        }
                        Self.clearQueueRow(db: db,
                                           recordName: id.recordName,
                                           upTo: watermarks[id.recordName])
                    }
                }
                for record in saved { enqueuedAt[record.recordID.recordName] = nil }
                for id in deleted { enqueuedAt[id.recordName] = nil }
            } catch {
                AppLogger.log(tag: "SyncEngine", "Post-send bookkeeping failed: \(error)")
            }
        }

        for failure in e.failedRecordSaves {
            await handleFailedSave(failure, syncEngine: syncEngine)
        }

        for (recordID, error) in e.failedRecordDeletes {
            switch error.code {
            case .unknownItem:
                // Already gone on the server — the outcome we wanted.
                try? await DatabaseManager.shared.dbQueue.write { db in
                    Self.clearQueueRow(db: db, recordName: recordID.recordName, upTo: nil)
                }
            default:
                AppLogger.log(tag: "SyncEngine",
                              "Delete failed \(recordID.recordName): \(error)")
            }
        }
    }

    private func handleFailedSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine
    ) async {
        let record = failure.record
        let name = record.recordID.recordName

        switch failure.error.code {

        case .serverRecordChanged:
            // Merge against the ancestor, write the result locally so this
            // device converges too, and re-queue so the merged version reaches
            // the server.
            guard let server = failure.error.serverRecord else {
                AppLogger.log(tag: "SyncEngine", "Conflict without server record: \(name)")
                return
            }
            let merged = SyncMerge.resolve(client: failure.error.clientRecord ?? record,
                                           server: server,
                                           ancestor: failure.error.ancestorRecord)

            // Cache the server's system fields BEFORE re-queueing. Without
            // this the retry rebuilds its record from the database through
            // `seededRecord`, finds no cached tag, and pushes as an insert
            // again — so CloudKit answers "record to insert already exists"
            // and the same conflict repeats forever.
            //
            // That deadlock is not hypothetical: it is what the first real
            // run against CloudKit did, 250 records looping with no record
            // ever reaching the server. Any device whose metadata cache is
            // empty while the zone already holds its records — a reinstall, a
            // restore from backup, a cleared cache — lands in it.
            tally.conflicts += 1
            await applyMerged(merged, cacheSystemFieldsFrom: server)
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            AppLogger.log(tag: "SyncEngine", "Merged conflict for \(name)")

        case .zoneNotFound:
            // The zone was deleted out from under us. Recreate it and re-push
            // everything — the local database is the user's library and must
            // not be discarded because a zone vanished.
            try? await DatabaseManager.shared.dbQueue.write { db in
                try SyncRecordMetadata.deleteAll(db: db)
            }
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

        case .unknownItem:
            // Referenced something the server no longer has. Drop the tag so
            // the next push creates it fresh.
            if let parsed = CKRecordName.parse(name) {
                try? await DatabaseManager.shared.dbQueue.write { db in
                    try SyncRecordMetadata.delete(db: db, type: parsed.type, recordName: name)
                }
            }
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

        case .networkFailure, .networkUnavailable, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            // Transient. CKSyncEngine keeps the change pending and retries with
            // backoff; doing anything here would fight it.
            break

        case .quotaExceeded:
            AppLogger.log(tag: "SyncEngine", "iCloud quota exceeded — sync paused for \(name)")

        default:
            AppLogger.log(tag: "SyncEngine", "Save failed \(name): \(failure.error)")
        }
    }

    /// Emits one line describing what the cycle actually did, then resets.
    /// Silent when nothing happened, so an idle app stays quiet.
    private func flushTally() {
        guard !tally.isEmpty else { return }
        AppLogger.log(tag: "SyncEngine", """
            cycle: fetched \(tally.fetched) (applied \(tally.applied),             deferred \(tally.deferred), deletes \(tally.deleted)) ·             sent \(tally.sent) (deletes \(tally.sentDeletes),             conflicts \(tally.conflicts), failed \(tally.failed))
            """)
        tally = Tally()
    }

    // MARK: - Account and database changes

    private func handleAccountChange(_ e: CKSyncEngine.Event.AccountChange) async {
        switch e.changeType {
        case .signIn:
            // A fresh account: everything local is unsent as far as the new
            // account's zone is concerned.
            try? await DatabaseManager.shared.dbQueue.write { db in
                try SyncRecordMetadata.deleteAll(db: db)
            }
            await enqueuePendingChanges()

        case .signOut, .switchAccounts:
            // Tags and tokens describe a zone this device can no longer reach.
            // Local data stays — it is the user's library, not a cache.
            try? await DatabaseManager.shared.dbQueue.write { db in
                try SyncRecordMetadata.deleteAll(db: db)
            }
            SyncStateStore.reset()
            AppLogger.log(tag: "SyncEngine", "Account changed — sync state cleared")

        @unknown default:
            break
        }
    }

    private func handleDatabaseChanges(_ e: CKSyncEngine.Event.FetchedDatabaseChanges) async {
        for deletion in e.deletions where deletion.zoneID == zoneID {
            AppLogger.log(tag: "SyncEngine",
                          "Zone removed (\(deletion.reason)) — re-uploading local library")
            try? await DatabaseManager.shared.dbQueue.write { db in
                try SyncRecordMetadata.deleteAll(db: db)
            }
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            await enqueueEverything()
        }
    }

    // MARK: - Queue helpers

    /// Deletes a processed CDC row, keeping any row re-queued after the push
    /// began. `upTo` nil means "delete regardless", used when the record is
    /// known to be gone.
    nonisolated private static func clearQueueRow(db: Database, recordName: String, upTo queuedAt: String?) {
        guard let parsed = CKRecordName.parse(recordName) else { return }
        do {
            if let queuedAt {
                try db.execute(sql: """
                    DELETE FROM cloudkit_pending_changes
                    WHERE recordType = ? AND recordID = ? AND queuedAt <= ?
                    """, arguments: [parsed.type, parsed.localID, queuedAt])
            } else {
                try db.execute(sql: """
                    DELETE FROM cloudkit_pending_changes
                    WHERE recordType = ? AND recordID = ?
                    """, arguments: [parsed.type, parsed.localID])
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Queue cleanup failed for \(recordName): \(error)")
        }
    }

    /// Removes a CDC entry from inside an already-open write transaction, so a
    /// record we just pulled is not immediately pushed back.
    nonisolated static func removeFromQueue(db: Database, type: String, id: String) {
        do {
            try db.execute(
                sql: "DELETE FROM cloudkit_pending_changes WHERE recordType = ? AND recordID = ?",
                arguments: [type, id])
        } catch {
            AppLogger.log(tag: "SyncEngine", "removeFromQueue failed for \(type)/\(id): \(error)")
        }
    }
}
