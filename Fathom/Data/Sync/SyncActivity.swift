import Combine
import Foundation

/// What sync is doing right now, in terms the UI can show.
///
/// The engine deals in records, batches and zone changes; a reader only needs
/// to know whether their library is still arriving. This translates one into
/// the other, and holds the two judgements that keep the UI honest:
///
/// 1. **Nothing is shown for a sync that finds nothing.** Every foreground
///    fetch would otherwise flash a banner, including the many that have no
///    work to do. The banner waits until a record actually arrives.
/// 2. **The first-run screen never flashes.** A device with an empty library
///    and an empty iCloud zone finishes in well under a second, and a
///    full-screen takeover for that long is worse than no takeover at all.
@MainActor
final class SyncActivity: ObservableObject {

    static let shared = SyncActivity()

    enum Phase: Equatable {
        /// Nothing to say.
        case idle
        /// A fetch is running.
        case gathering
        /// It finished, and something arrived. Held briefly so the change is
        /// legible rather than a flicker.
        case settled
    }

    @Published fileprivate(set) var phase: Phase = .idle

    /// Records applied in the current cycle. CloudKit does not say up front how
    /// many are coming, so this counts up rather than filling a bar — showing a
    /// percentage would mean inventing a denominator.
    @Published fileprivate(set) var received = 0

    /// True when this device had no library of its own when sync started, which
    /// is the only case that earns a full screen.
    fileprivate(set) var isFirstSync = false

    /// Whether the first-run surface should be on screen.
    @Published fileprivate(set) var isPresentingSetup = false

    /// Worth showing a banner: something actually arrived.
    var hasArrivals: Bool { received > 0 }

    private var presentTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    private init() {}

    // MARK: - Engine hooks

    /// Called once when the engine starts, before any fetch.
    ///
    /// Only reached when iCloud is actually available — `SyncBootstrap` returns
    /// early otherwise — so a signed-out reader never waits on a sync that
    /// cannot happen.
    func prime(firstSync: Bool) {
        isFirstSync = firstSync
    }

    func begin() {
        settleTask?.cancel()
        guard phase != .gathering else { return }
        phase = .gathering
        received = 0

        guard isFirstSync else { return }
        presentTask?.cancel()
        presentTask = Task { [weak self] in
            // A first sync with nothing waiting for it is over in a few hundred
            // milliseconds. Waiting this long before taking the screen means
            // that case shows nothing at all, instead of a takeover that
            // appears and disappears before it can be read.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.phase == .gathering else { return }
            self.isPresentingSetup = true
        }
    }

    func note(received count: Int) {
        guard count > 0 else { return }
        received += count
    }

    #if DEBUG
    /// Drives the sync surfaces without a sync, for looking at them.
    ///
    /// Both are otherwise nearly impossible to see on purpose: the setup screen
    /// appears once, on a clean install, only when there is real data in iCloud
    /// to receive, and the banner only while records happen to be in flight.
    /// Iterating on a design you can only reach by wiping the app is how a
    /// screen ends up unreviewed.
    ///
    /// Pass `-FathomPreviewSync setup`, `banner`, or `done` (the completion
    /// state held still, which otherwise lasts about two seconds).
    static func startPreviewIfRequested() {
        let mode = UserDefaults.standard.string(forKey: "FathomPreviewSync")
        guard let mode else { return }

        let activity = SyncActivity.shared

        if mode == "done" {
            activity.received = 312
            activity.phase = .settled
            return
        }

        activity.isFirstSync = (mode == "setup")
        activity.phase = .gathering
        activity.isPresentingSetup = (mode == "setup")

        // Count up the way a real fetch does, so the numeric transition and the
        // travelling rule can be judged in motion rather than as a still.
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(220))
                activity.received += Int.random(in: 3...11)
            }
        }
    }
    #endif

    func finish() {
        presentTask?.cancel()
        isPresentingSetup = false
        // The first sync is the only one that earns the screen. Once it is
        // done, this device has a library.
        isFirstSync = false

        guard hasArrivals else {
            phase = .idle
            return
        }

        phase = .settled
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, let self else { return }
            self.phase = .idle
            self.received = 0
        }
    }
}
