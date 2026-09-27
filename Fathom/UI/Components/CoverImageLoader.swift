import UIKit

/// Loads cover art without touching the main thread.
///
/// Reading a cover blocks in `pread` until iCloud materialises the file, which
/// on a clean install means every cover at once. Doing that on the main thread
/// froze the app for 13 seconds.
///
/// The obvious spelling — `Task.detached { BookFileStore.coverImage(...) }` at
/// each call site — looks correct and is not, because
/// `SWIFT_DEFAULT_ACTOR_ISOLATION` is MainActor: any helper the closure calls
/// that does not say `nonisolated` is a *main-actor* helper, and calling it
/// hops the detached task straight back onto the main thread. That happened
/// twice in a row here, first through `BookFileStore` itself and then through a
/// `private static func` on a View that merely forwarded to it. Neither was
/// visible at the call site.
///
/// So the detaching lives here, once, in a `nonisolated` type. Call sites
/// `await` this and have nothing left to get wrong.
nonisolated enum CoverImageLoader {

    /// The decoded cover for `filename`, or nil if there is none.
    static func image(for filename: String?) async -> UIImage? {
        guard let filename else { return nil }
        return await offMain { BookFileStore.coverImage(for: filename) }
    }

    /// Runs `work` off the main thread and returns its result.
    ///
    /// `work` is deliberately **synchronous**. A hop to the main actor needs a
    /// suspension point, and `Task.detached` takes an async closure — so a call
    /// to a main-actor helper inside one becomes an implicit await and the work
    /// returns to the main thread. A synchronous closure has nowhere to suspend,
    /// so it cannot be pulled back. That is the difference between this and the
    /// spelling that froze the app.
    ///
    /// It is a guard rail rather than a guarantee: under Swift 5 language mode
    /// the isolation violation is only a warning. Everything reachable from
    /// here is explicitly `nonisolated` so there is no violation in the first
    /// place. `MainActorIsolationTests` pins both halves down.
    ///
    /// The work runs on a dedicated, bounded queue — not in a detached task.
    /// A detached task runs on Swift's cooperative pool, which has one thread
    /// per core and assumes nothing blocks it. A cover read blocks in `pread`
    /// until iCloud delivers the file, so a grid of not-yet-downloaded covers
    /// could occupy every pool thread and stall all of the app's async work —
    /// sync, database reads, everything — until the downloads finished.
    static func offMain<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            ioQueue.addOperation {
                continuation.resume(returning: work())
            }
        }
    }

    /// OperationQueue is documented as thread-safe; it is just not marked
    /// Sendable.
    nonisolated(unsafe) private static let ioQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.fathom.cover-io"
        queue.qualityOfService = .utility
        // Enough to overlap reads; few enough that a wall of blocked reads
        // cannot turn into a thread explosion.
        queue.maxConcurrentOperationCount = 4
        return queue
    }()
}
