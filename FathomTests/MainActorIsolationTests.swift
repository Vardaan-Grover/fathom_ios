import Foundation
import Testing

@testable import Fathom

/// A plain enum with no isolation written down — exactly what `BookFileStore`
/// and `ICloudFileStore` used to be.
private enum UnannotatedStore {
    static func isMainThread() -> Bool { Thread.isMainThread }
}

/// `SWIFT_DEFAULT_ACTOR_ISOLATION` is MainActor, which means a type with no
/// isolation annotation is a *main-actor* type. That is easy to forget and
/// invisible at the call site: `Task.detached` genuinely starts off the main
/// thread, and then the first call into an unannotated type hops right back.
///
/// Two rounds of "this runs off the main actor" comments were wrong for exactly
/// this reason, and the cost was a 14-second freeze on every clean install —
/// `pread`, inside ImageIO, inside a cover load, on the main thread. These
/// tests pin the behaviour down so it cannot quietly come back.
struct MainActorIsolationTests {

    @Test("A detached task starts off the main thread")
    func detachedStartsOffMain() async {
        // The baseline. Detaching is not the broken part.
        let onMain = await Task.detached(priority: .utility) { Thread.isMainThread }.value
        #expect(!onMain)
    }

    @Test("An unannotated type pulls a detached task back onto the main thread")
    func unannotatedTypeHopsToMain() async {
        // This is the trap, asserted rather than described. If it ever fails,
        // the project's default isolation changed — at which point the
        // `nonisolated` annotations below may no longer be load-bearing, and
        // the comments explaining them will need revisiting.
        let onMain = await Task.detached(priority: .utility) {
            UnannotatedStore.isMainThread()
        }.value
        #expect(onMain, "default actor isolation is no longer MainActor")
    }

    @Test("BookFileStore does not drag its caller onto the main thread")
    func bookFileStoreStaysOffMain() async {
        // Reading a cover blocks in pread until iCloud materialises the file.
        // Doing that on the main thread is the freeze, so this is the
        // regression test for it.
        let onMain = await Task.detached(priority: .utility) { () -> Bool in
            _ = BookFileStore.coverURL(for: "probe-does-not-exist.png")
            return Thread.isMainThread
        }.value
        #expect(!onMain)
    }

    @Test("CoverImageLoader runs its work off the main thread")
    func coverImageLoaderStaysOffMain() async {
        // The one place cover reads are allowed to detach. Every call site goes
        // through here precisely so none of them can reintroduce a main-actor
        // hop of its own.
        let onMain = await CoverImageLoader.offMain { Thread.isMainThread }
        #expect(!onMain)
    }

    @Test("A synchronous off-main closure cannot be hopped away")
    func synchronousClosureStaysOffMain() async {
        // The hop needs a suspension point. `Task.detached` takes an *async*
        // closure, so a call to a main-actor helper inside it becomes an
        // implicit await and the work lands back on the main thread — that is
        // the bug above, and it is why `offMain` takes a *synchronous* closure
        // instead. Same main-actor helper, no hop.
        //
        // Under Swift 5 language mode the isolation violation is a warning
        // rather than an error, so this is a guard rail, not a guarantee.
        // Everything reached from `offMain` is explicitly `nonisolated` so that
        // there is no violation to begin with.
        let onMain = await CoverImageLoader.offMain { UnannotatedStore.isMainThread() }
        #expect(!onMain)
    }

    @Test("ICloudFileStore does not drag its caller onto the main thread")
    func icloudFileStoreStaysOffMain() async {
        // Same reasoning for the launch path: resolving the ubiquity container
        // is ~870ms of I/O, and SyncBootstrap being nonisolated does not help
        // if the store it calls is main-actor isolated.
        let onMain = await Task.detached(priority: .utility) { () -> Bool in
            _ = ICloudFileStore.shared.isAvailable
            return Thread.isMainThread
        }.value
        #expect(!onMain)
    }
}
