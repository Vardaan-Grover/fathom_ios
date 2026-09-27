import Foundation
import GRDB

/// Marks a database transaction as "sync is writing this", so the CDC and
/// modifiedAt triggers stand aside.
///
/// A row that arrives from CloudKit is not a local change: queueing it would
/// push it straight back, and restamping its `modifiedAt` would replace the
/// other device's time with ours. The triggers check `sync_apply_context`
/// (migration v35) and do nothing while it is raised.
///
/// The previous approach let the triggers fire and then deleted the queue row
/// afterwards — which also deleted any genuine local edit that happened to be
/// queued for the same record, silently unsyncing it.
///
/// The context is a counter so scopes nest. It is only ever changed inside a
/// write transaction, so a crash rolls it back; `DatabaseManager` also clears
/// it at launch as a second line of defence.
nonisolated enum SyncApplyContext {

    /// Runs `body` with the sync triggers suppressed. Must be called inside a
    /// write transaction.
    static func perform<T>(_ db: Database, _ body: () throws -> T) throws -> T {
        try db.execute(sql: "UPDATE sync_apply_context SET active = active + 1 WHERE id = 1")
        defer {
            try? db.execute(sql: """
                UPDATE sync_apply_context SET active = MAX(active - 1, 0) WHERE id = 1
                """)
        }
        return try body()
    }
}
