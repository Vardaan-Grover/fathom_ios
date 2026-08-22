import Foundation

#if DEBUG

/// Reports when the main thread stops responding.
///
/// Added because "the app felt unresponsive" and "the main thread was blocked"
/// are different claims, and separating them by inspecting code has already
/// cost more than one build cycle. This measures it directly: a background
/// thread hands a token to the main queue and times how long it takes to come
/// back. If the main thread is busy, the round trip is the length of the block.
///
/// DEBUG only. It is a diagnostic, not a feature, and it costs a wake-up every
/// `interval` seconds.
enum MainThreadWatchdog {

    /// How often to probe.
    private static let interval: TimeInterval = 0.25

    /// Round trips longer than this are worth reporting. A frame is 16ms, so
    /// anything past this is visible stutter rather than ordinary scheduling.
    private static let threshold: TimeInterval = 0.5

    nonisolated(unsafe) private static var running = false

    static func start() {
        guard !running else { return }
        running = true

        Thread.detachNewThread {
            Thread.current.name = "fathom.watchdog"
            var worstReported: TimeInterval = 0

            while true {
                let sent = Date()
                let signal = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { signal.signal() }

                // Generous cap: the point is to measure long blocks, not to
                // give up on them.
                _ = signal.wait(timeout: .now() + 30)
                let blocked = Date().timeIntervalSince(sent)

                if blocked > threshold {
                    // Only report a block that is worse than the last one, so a
                    // sustained freeze produces a few escalating lines rather
                    // than a wall of them.
                    if blocked > worstReported * 1.5 {
                        worstReported = blocked
                        AppLogger.log(tag: "Watchdog",
                                      "main thread blocked ~\(Int(blocked * 1000))ms")
                    }
                } else {
                    worstReported = 0
                }

                Thread.sleep(forTimeInterval: interval)
            }
        }
    }
}

#endif
