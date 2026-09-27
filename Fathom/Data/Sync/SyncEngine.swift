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

    var recordName: String { CKRecordName.make(type: recordType, localID: recordID) }
}

// MARK: - SyncEngine

/// Drives CloudKit sync for the private database.
///
/// Change *detection* is the SQLite triggers that write into
/// `cloudkit_pending_changes` — they catch every local mutation without any
/// call site having to remember to announce it. Writes made by sync itself do
/// not fire them (see `SyncApplyContext`). Change *transport* is `CKSyncEngine`,
/// which owns server change tokens, batching, backoff, throttling, account
/// changes and retries.
///
/// Conflicts are resolved by `SyncMerge` — a three-way merge of this device's
/// current state, the server's record and the last version both shared — per
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

    /// Guards `start()` across its suspension points, so two callers cannot
    /// both pass the `engine == nil` check and build two engines.
    private var isStarting = false

    private var cdcObserver: AnyDatabaseCancellable?
    private var notificationTokens: [NSObjectProtocol] = []

    /// The queue timestamp each record carried when its batch was *built*.
    ///
    /// On a successful send only queue rows at or before this stamp are
    /// cleared, so an edit made while the push was in flight survives and is
    /// pushed again. The stamp is captured before the record's data is read,
    /// never later: it used to be refreshed every time the queue changed, so an
    /// edit made mid-push raised it, the successful send of the *old* data then
    /// cleared the *new* row, and the edit never reached iCloud.
    ///
    /// A record with no entry had no queue row when its batch was built, so
    /// any row present afterwards is newer and must survive.
    private var sendWatermarks: [String: String] = [:]

    /// The `queuedAt` last handed to CKSyncEngine per record, so an observation
    /// that re-reads the whole queue only enqueues what actually changed.
    private var enqueuedStamps: [String: String] = [:]

    /// Set when a zone fetch in the current cycle reported an error, so the
    /// cycle is not recorded as a successful sync.
    private var cycleHadFetchError = false

    /// Tallies for one fetch/send cycle, logged as a single summary line.
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
    func noteDeferred(_ count: Int = 1) { tally.deferred += count }

    // MARK: - Lifecycle

    /// Creates the engine. Called once per launch by `SyncBootstrap`, as early
    /// as possible: CKSyncEngine starts listening for pushes and scheduled
    /// syncs only once it exists, and it waits by itself for an iCloud account,
    /// so there is no reason to gate it on anything.
    func start() async {
        guard engine == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        let restored = SyncStateStore.load()

        // Only a device with no library *and* no sync history gets the
        // full-screen arrival surface. Keying it on the library alone showed
        // "Bringing your library across" to every reader with no books yet on
        // every slow cold launch — with nothing to bring.
        let bookCount = (try? await DatabaseManager.shared.dbQueue.read { db in
            try Book.fetchCount(db)
        }) ?? 0
        await SyncActivity.shared.prime(firstSync: restored == nil && bookCount == 0)

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
        await enqueueUnsyncedSingletons()
        startCDCObservation()
        startNotificationObservers()
        await refreshAccountStatus()

        AppLogger.log(tag: "SyncEngine", "Started (zone \(Self.zoneName))")

        // Pull whatever changed while this device was not running. The
        // foreground hook in FathomApp can arrive before this point on a cold
        // launch, so start() fetches for itself. Parents may have arrived in an
        // earlier session, so drain before the fetch as well as after it.
        await drainDeferred()
        await fetchChangesIfNeeded()
        AppLogger.log(tag: "SyncEngine", "startup fetch complete")
    }

    /// Foreground refresh. CKSyncEngine also syncs on its own schedule; this
    /// makes a returning user's first screen current without waiting for it.
    func fetchChangesIfNeeded() async {
        guard let engine else {
            AppLogger.log(tag: "SyncEngine", "foreground fetch beat startup — start() will cover it")
            return
        }
        do {
            try await engine.fetchChanges()
        } catch {
            AppLogger.log(tag: "SyncEngine", "Manual fetch failed: \(error)")
        }
    }

    /// Pushes everything pending before the app is suspended.
    ///
    /// Positions and settings are flushed to disk when the app leaves the
    /// foreground, but their sync notification hops through the main queue and
    /// CKSyncEngine then waits for its own schedule — by which time the app is
    /// usually suspended, so the last session's position reached iCloud only
    /// on the next launch and the other device opened the book at the old
    /// page. The caller holds a background task around this.
    func sendBeforeSuspension(positions: Set<UUID>, settingsChanged: Bool) async {
        guard let engine else { return }
        for bookID in positions {
            enqueueSingleton(type: CKRecordType.readingPosition, localID: bookID.uuidString)
        }
        if settingsChanged {
            enqueueSingleton(type: CKRecordType.readerSettings, localID: "current")
        }
        await enqueuePendingChanges()
        do {
            try await engine.sendChanges()
        } catch {
            AppLogger.log(tag: "SyncEngine", "Background send failed: \(error)")
        }
    }

    /// Reflects the iCloud account's state in the UI. CKSyncEngine handles the
    /// account itself; this only tells the reader why nothing is syncing.
    private func refreshAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                await SyncActivity.shared.clearProblem()
            case .noAccount:
                await SyncActivity.shared.report(.noAccount)
            case .restricted, .temporarilyUnavailable:
                await SyncActivity.shared.report(.accountUnavailable)
            case .couldNotDetermine:
                break
            @unknown default:
                break
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Account status check failed: \(error)")
        }
    }

    // MARK: - Local change detection

    private static let queueSQL = """
        SELECT recordType, recordID, operation, queuedAt
        FROM   cloudkit_pending_changes
        ORDER  BY queuedAt ASC
        """

    private func startCDCObservation() {
        let observation = ValueObservation.tracking { db -> [PendingChangeRow] in
            try PendingChangeRow.fetchAll(db, sql: Self.queueSQL)
        }

        cdcObserver = observation.start(
            in: DatabaseManager.shared.dbQueue,
            scheduling: .async(onQueue: .global(qos: .utility)),
            onError: { error in
                AppLogger.log(tag: "SyncEngine", "CDC observation error: \(error)")
            },
            onChange: { [weak self] rows in
                Task { await self?.enqueue(rows, isFullQueue: true) }
            }
        )
    }

    private func enqueuePendingChanges() async {
        do {
            let rows = try await DatabaseManager.shared.dbQueue.read { db in
                try PendingChangeRow.fetchAll(db, sql: Self.queueSQL)
            }
            enqueue(rows, isFullQueue: true, force: true)
        } catch {
            AppLogger.log(tag: "SyncEngine", "Failed to read pending changes: \(error)")
        }
    }

    /// Hands queue rows to CKSyncEngine.
    ///
    /// - Parameters:
    ///   - isFullQueue: `rows` is the whole queue, so records missing from it
    ///     have left it and their remembered stamps can go.
    ///   - force: enqueue even rows whose stamp was already handed over — used
    ///     after a send, when CKSyncEngine has dropped a change whose newer
    ///     queue row survived.
    private func enqueue(_ rows: [PendingChangeRow], isFullQueue: Bool, force: Bool = false) {
        guard let engine else { return }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        var superseded: [CKSyncEngine.PendingRecordZoneChange] = []
        var present = Set<String>()

        for row in rows {
            // AIConversation rows can still exist from builds predating v26.
            guard CKRecordType.all.contains(row.recordType) else { continue }

            let name = row.recordName
            present.insert(name)
            if !force, enqueuedStamps[name] == row.queuedAt { continue }
            enqueuedStamps[name] = row.queuedAt

            let id = CKRecord.ID(recordName: name, zoneID: zoneID)
            if row.operation == "delete" {
                changes.append(.deleteRecord(id))
                superseded.append(.saveRecord(id))
            } else {
                changes.append(.saveRecord(id))
                superseded.append(.deleteRecord(id))
            }
        }

        if isFullQueue {
            enqueuedStamps = enqueuedStamps.filter { present.contains($0.key) }
        }

        guard !changes.isEmpty else { return }
        // A save and a delete for the same record must not both be pending:
        // whichever the queue holds now is the current intent.
        engine.state.remove(pendingRecordZoneChanges: superseded)
        engine.state.add(pendingRecordZoneChanges: changes)
        AppLogger.log(tag: "SyncEngine", "queued \(changes.count) local change(s) to push")
    }

    /// Queues a record that has no CDC trigger behind it — the singletons
    /// that live in file-backed stores rather than SQLite tables.
    private func enqueueSingleton(type: CKRecord.RecordType, localID: String) {
        guard let engine else { return }
        let id = CKRecordName.id(type: type, localID: localID, zoneID: zoneID)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    private func enqueueSingletonDelete(type: CKRecord.RecordType, localID: String) {
        guard let engine else { return }
        let id = CKRecordName.id(type: type, localID: localID, zoneID: zoneID)
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
    }

    /// Queues any singleton the server has never acknowledged.
    ///
    /// Singletons are only pushed when they change, so a reading position
    /// recorded before sync existed — or before a zone reset — would otherwise
    /// never reach iCloud, and a new device would open those books at the
    /// start. Settings and profile are only offered when the reader actually
    /// customised them: pushing a fresh install's defaults would overwrite the
    /// reader's real settings on every other device.
    private func enqueueUnsyncedSingletons() async {
        let candidates = await singletonCandidates()
        let unsynced: [(String, String)]
        do {
            unsynced = try await DatabaseManager.shared.dbQueue.read { db in
                try candidates.filter { type, localID in
                    let name = CKRecordName.make(type: type, localID: localID)
                    return try !SyncRecordMetadata.exists(db: db, type: type, recordName: name)
                }
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Singleton check failed: \(error)")
            return
        }
        for (type, localID) in unsynced {
            enqueueSingleton(type: type, localID: localID)
        }
        if !unsynced.isEmpty {
            AppLogger.log(tag: "SyncEngine", "queued \(unsynced.count) never-synced singleton(s)")
        }
    }

    /// Every singleton this device holds a meaningful local value for.
    func singletonCandidates() async -> [(String, String)] {
        let stored = ReadingStateStore.shared.allBookIDs()
        let existing = (try? await DatabaseManager.shared.dbQueue.read { db in
            try stored.filter { try Book.exists(db, key: $0) }
        }) ?? []

        var out = existing.map { (CKRecordType.readingPosition, $0.uuidString) }
        if ReaderSettingsStore.shared.modifiedAt != nil {
            out.append((CKRecordType.readerSettings, "current"))
        }
        if UserProfileStore.shared.modifiedAt != nil {
            out.append((CKRecordType.userProfile, "current"))
        }
        return out
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
            forName: ReadingStateStore.didRemoveNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let bookID = note.userInfo?["bookID"] as? UUID else { return }
            Task { await self?.enqueueSingletonDelete(type: CKRecordType.readingPosition,
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

        // Before any record's data is read — see `sendWatermarks`.
        await captureWatermarks(for: pending)

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.recordToSave(recordID)
        }
    }

    private func captureWatermarks(for pending: [CKSyncEngine.PendingRecordZoneChange]) async {
        let stamps: [String: String]
        do {
            stamps = try await DatabaseManager.shared.dbQueue.read { db in
                var out: [String: String] = [:]
                for row in try PendingChangeRow.fetchAll(db, sql: Self.queueSQL) {
                    out[row.recordName] = row.queuedAt
                }
                return out
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Watermark capture failed: \(error)")
            return
        }

        for change in pending {
            let name: String
            switch change {
            case .saveRecord(let id): name = id.recordName
            case .deleteRecord(let id): name = id.recordName
            @unknown default: continue
            }
            sendWatermarks[name] = stamps[name]
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {

        case .stateUpdate(let e):
            SyncStateStore.save(e.stateSerialization)

        case .accountChange(let e):
            await handleAccountChange(e, syncEngine: syncEngine)

        case .fetchedRecordZoneChanges(let e):
            tally.fetched += e.modifications.count
            tally.deleted += e.deletions.count
            let applied = await applyFetched(modifications: e.modifications, deletions: e.deletions)
            await SyncActivity.shared.note(received: applied)

        case .fetchedDatabaseChanges(let e):
            await handleDatabaseChanges(e, syncEngine: syncEngine)

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

        case .willFetchChanges:
            cycleHadFetchError = false
            await SyncActivity.shared.begin()

        case .didFetchChanges:
            flushTally()
            if !cycleHadFetchError {
                await SyncActivity.shared.markSynced()
            }
            await SyncActivity.shared.finish()

        case .didSendChanges:
            flushTally()

        case .willSendChanges, .willFetchRecordZoneChanges:
            break

        case .didFetchRecordZoneChanges(let e):
            if let error = e.error {
                cycleHadFetchError = true
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

        // Successful saves: cache the server's record so the next push carries
        // its change tag and the next conflict has a real ancestor, and clear
        // the queue rows the push covered.
        let saved = e.savedRecords
        let deleted = e.deletedRecordIDs
        let sentNames = Set(saved.map(\.recordID.recordName) + deleted.map(\.recordName))

        if !sentNames.isEmpty {
            let marks = sendWatermarks
            do {
                try await DatabaseManager.shared.dbQueue.write { db in
                    for record in saved {
                        try SyncRecordMetadata.save(db: db, record: record)
                        Self.clearQueueRow(db: db,
                                           recordName: record.recordID.recordName,
                                           upTo: marks[record.recordID.recordName])
                    }
                    for id in deleted {
                        if let parsed = CKRecordName.parse(id.recordName) {
                            try SyncRecordMetadata.delete(db: db,
                                                          type: parsed.type,
                                                          recordName: id.recordName)
                        }
                        Self.clearQueueRow(db: db,
                                           recordName: id.recordName,
                                           upTo: marks[id.recordName])
                    }
                }
            } catch {
                AppLogger.log(tag: "SyncEngine", "Post-send bookkeeping failed: \(error)")
            }
            for name in sentNames { sendWatermarks[name] = nil }

            // CKSyncEngine removes a change once it is sent. A queue row that
            // survived the cleanup is an edit made while the push was in
            // flight, so hand it back or it waits until the next launch.
            await requeueSurvivors(of: sentNames)
        }

        for failure in e.failedRecordSaves {
            await handleFailedSave(failure, syncEngine: syncEngine)
        }

        for (recordID, error) in e.failedRecordDeletes {
            switch error.code {
            case .unknownItem:
                // Already gone on the server — the outcome we wanted.
                try? await DatabaseManager.shared.dbQueue.write { db in
                    Self.removeFromQueue(db: db, recordName: recordID.recordName)
                }
            case .networkFailure, .networkUnavailable, .serviceUnavailable,
                 .requestRateLimited, .zoneBusy, .notAuthenticated, .operationCancelled,
                 .batchRequestFailed:
                break   // retried by CKSyncEngine
            default:
                AppLogger.log(tag: "SyncEngine",
                              "Delete failed \(recordID.recordName): \(error)")
            }
        }
    }

    private func requeueSurvivors(of names: Set<String>) async {
        do {
            let rows = try await DatabaseManager.shared.dbQueue.read { db in
                try PendingChangeRow.fetchAll(db, sql: Self.queueSQL)
            }
            let survivors = rows.filter { names.contains($0.recordName) }
            if !survivors.isEmpty {
                enqueue(survivors, isFullQueue: false, force: true)
            }
        } catch {
            AppLogger.log(tag: "SyncEngine", "Survivor check failed: \(error)")
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
            // Merge the server's version with this device's *current* state —
            // not the record that was sent, which may already be out of date —
            // write the result locally, and re-queue so it reaches the server.
            // The server's record is cached before the retry is built, so the
            // retry carries its change tag instead of looping as an insert.
            guard let server = failure.error.serverRecord else {
                AppLogger.log(tag: "SyncEngine", "Conflict without server record: \(name)")
                return
            }
            tally.conflicts += 1
            await resolveConflict(recordID: record.recordID,
                                  server: server,
                                  reportedAncestor: failure.error.ancestorRecord)
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            AppLogger.log(tag: "SyncEngine", "Merged conflict for \(name)")

        case .zoneNotFound:
            // The zone is gone — most often because the reader deleted Fathom's
            // iCloud data. Recreate it and push this record; the cached tags
            // describe records that no longer exist, so drop them all. The rest
            // of the library is re-uploaded only when the zone deletion event
            // says it should be (see `handleDatabaseChanges`).
            try? await DatabaseManager.shared.dbQueue.write { db in
                try SyncRecordMetadata.deleteAll(db: db)
            }
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

        case .unknownItem:
            // The save carried a tag for a record the server no longer has.
            await handleVanishedRecord(record.recordID, syncEngine: syncEngine)

        case .networkFailure, .networkUnavailable, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .notAuthenticated, .operationCancelled,
             .batchRequestFailed:
            // Transient, or a side effect of another record in the same batch.
            // CKSyncEngine keeps the change pending and retries with backoff.
            break

        case .quotaExceeded:
            AppLogger.log(tag: "SyncEngine", "iCloud quota exceeded — waiting on \(name)")
            await SyncActivity.shared.report(.quotaExceeded)

        default:
            AppLogger.log(tag: "SyncEngine", "Save failed \(name): \(failure.error)")
            await SyncActivity.shared.report(.failing(failure.error.localizedDescription))
        }
    }

    /// A save failed with `unknownItem`: the record existed on the server when
    /// this device last saw it, and does not now.
    ///
    /// For types the app hard-deletes — books, shelves, completions and shelf
    /// memberships, which go when their book or shelf does — that means another
    /// device deleted it, and the right answer is to delete it here too. The
    /// previous handler re-uploaded the local copy, so opening a book on one
    /// device (which touches `lastReadAt`) resurrected it everywhere after it
    /// had been deleted on another — with its file already gone.
    ///
    /// Everything else is never deleted on purpose, so the local copy is
    /// re-uploaded as a new record.
    private func handleVanishedRecord(_ recordID: CKRecord.ID, syncEngine: CKSyncEngine) async {
        guard let parsed = CKRecordName.parse(recordID.recordName) else { return }

        switch parsed.type {
        case CKRecordType.book, CKRecordType.bookCategory,
             CKRecordType.bookCompletion, CKRecordType.bookCategoryMembership:
            AppLogger.log(tag: "SyncEngine",
                          "\(recordID.recordName) was deleted on another device — deleting here")
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            if await applyRemoteDeletion(recordID) {
                await postRemoteChangeNotification()
            }

        default:
            try? await DatabaseManager.shared.dbQueue.write { db in
                try SyncRecordMetadata.delete(db: db, type: parsed.type,
                                              recordName: recordID.recordName)
            }
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        }
    }

    /// Emits one line describing what the cycle actually did, then resets.
    /// Silent when nothing happened, so an idle app stays quiet.
    private func flushTally() {
        guard !tally.isEmpty else { return }
        let t = tally
        AppLogger.log(tag: "SyncEngine",
                      "cycle: fetched \(t.fetched) (applied \(t.applied), deferred \(t.deferred), "
                      + "deletes \(t.deleted)) · sent \(t.sent) (deletes \(t.sentDeletes), "
                      + "conflicts \(t.conflicts), failed \(t.failed))")
        tally = Tally()
    }

    // MARK: - Account and database changes

    /// The library on this device belongs to the reader, not to an account, so
    /// it is never deleted here. A sign-in — whether the first, or a switch to
    /// a different Apple ID — uploads all of it into that account, merging
    /// with anything already there. A sign-out keeps it on the device, and it
    /// is uploaded again at the next sign-in.
    private func handleAccountChange(_ e: CKSyncEngine.Event.AccountChange,
                                     syncEngine: CKSyncEngine) async {
        // Cached tags and parked records describe the previous account's zone.
        try? await DatabaseManager.shared.dbQueue.write { db in
            try SyncRecordMetadata.deleteAll(db: db)
            try SyncDeferredApplies.removeAll(db: db)
        }
        sendWatermarks = [:]
        enqueuedStamps = [:]

        switch e.changeType {
        case .signIn, .switchAccounts:
            AppLogger.log(tag: "SyncEngine", "Account signed in — uploading the local library")
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            await enqueueEverything()
            await SyncActivity.shared.clearProblem()

        case .signOut:
            AppLogger.log(tag: "SyncEngine", "Account signed out — library kept on device")
            await SyncActivity.shared.report(.noAccount)

        @unknown default:
            break
        }
    }

    private func handleDatabaseChanges(_ e: CKSyncEngine.Event.FetchedDatabaseChanges,
                                       syncEngine: CKSyncEngine) async {
        for deletion in e.deletions where deletion.zoneID == zoneID {
            switch deletion.reason {
            case .purged:
                // The reader deleted Fathom's iCloud data from Settings. Keep
                // the library on this device, but do not put it back: that is
                // what they asked for. Changes made from now on sync again —
                // the first one recreates the zone.
                AppLogger.log(tag: "SyncEngine",
                              "iCloud data deleted by the user — keeping the library on device, not re-uploading")
                try? await DatabaseManager.shared.dbQueue.write { db in
                    try SyncRecordMetadata.deleteAll(db: db)
                    try SyncDeferredApplies.removeAll(db: db)
                    try db.execute(sql: "DELETE FROM cloudkit_pending_changes")
                }
                syncEngine.state.remove(
                    pendingRecordZoneChanges: syncEngine.state.pendingRecordZoneChanges)
                sendWatermarks = [:]
                enqueuedStamps = [:]

            default:
                // Deleted some other way, or reset because the reader's
                // end-to-end encryption keys were reset. The server has
                // nothing; the local library is the only copy.
                AppLogger.log(tag: "SyncEngine",
                              "Zone removed (\(deletion.reason)) — re-uploading the local library")
                try? await DatabaseManager.shared.dbQueue.write { db in
                    try SyncRecordMetadata.deleteAll(db: db)
                }
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                await enqueueEverything()
            }
        }
    }

    // MARK: - Queue helpers

    /// Deletes a processed CDC row, keeping any row re-queued after the batch
    /// was built. A nil `upTo` means no row existed then, so nothing is
    /// deleted — whatever is there now is a newer change.
    nonisolated private static func clearQueueRow(db: Database, recordName: String, upTo queuedAt: String?) {
        guard let queuedAt, let parsed = CKRecordName.parse(recordName) else { return }
        do {
            try db.execute(sql: """
                DELETE FROM cloudkit_pending_changes
                WHERE recordType = ? AND recordID = ? AND queuedAt <= ?
                """, arguments: [parsed.type, parsed.localID, queuedAt])
        } catch {
            AppLogger.log(tag: "SyncEngine", "Queue cleanup failed for \(recordName): \(error)")
        }
    }

    /// Removes a record's CDC entry unconditionally — for a record known to be
    /// gone, where no pending local change can matter any more.
    nonisolated static func removeFromQueue(db: Database, recordName: String) {
        guard let parsed = CKRecordName.parse(recordName) else { return }
        removeFromQueue(db: db, type: parsed.type, id: parsed.localID)
    }

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
