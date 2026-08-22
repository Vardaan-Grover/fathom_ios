import Darwin
import Foundation

#if DEBUG

/// Reports when the main thread stops responding, and what it was doing.
///
/// Added because "the app felt unresponsive" and "the main thread was blocked"
/// are different claims, and separating them by inspecting code has already
/// cost more than one build cycle. This measures it directly: a background
/// thread hands a token to the main queue and times how long it takes to come
/// back. If the main thread is busy, the round trip is the length of the block.
///
/// The duration alone turned out not to be enough — it says a block happened,
/// not which code caused it, and three rounds of narrowing that down by reading
/// source produced two wrong answers. So when a block is detected the watchdog
/// also captures the main thread's call stack, which is what hang reporters
/// (KSCrash, Bugsnag, Firebase) do and the only thing that settles the question
/// rather than ranking suspects.
///
/// DEBUG only. It is a diagnostic, not a feature, and it costs a wake-up every
/// `interval` seconds.
enum MainThreadWatchdog {

    /// How often to probe.
    private static let interval: TimeInterval = 0.25

    /// Round trips longer than this are worth reporting. A frame is 16ms, so
    /// anything past this is visible stutter rather than ordinary scheduling.
    private static let threshold: TimeInterval = 0.5

    /// How deep to walk. Deeper than this and the useful frames are long past.
    private static let maximumFrames = 40

    nonisolated(unsafe) private static var running = false

    /// The main thread's mach port, captured by running a block on it. There is
    /// no way to ask for another thread's port by name, so it has to identify
    /// itself once.
    nonisolated(unsafe) private static var mainThread: thread_t = mach_port_t(MACH_PORT_NULL)

    /// Scratch space for program counters, allocated once. Nothing may be
    /// allocated while the main thread is suspended — if it is stopped holding
    /// the malloc lock, allocating here deadlocks the process. Collecting into
    /// this buffer is allocation-free; symbolication happens after the resume.
    nonisolated(unsafe) private static let addresses =
        UnsafeMutablePointer<UInt64>.allocate(capacity: maximumFrames)

    static func start() {
        guard !running else { return }
        running = true

        // Synchronously when possible: dispatching to a main thread that is
        // already busy means the port is not captured until the block clears,
        // and the sample we most want is the one taken during it.
        if Thread.isMainThread {
            mainThread = mach_thread_self()
        } else {
            DispatchQueue.main.async { mainThread = mach_thread_self() }
        }

        Thread.detachNewThread {
            Thread.current.name = "fathom.watchdog"
            var worstReported: TimeInterval = 0

            while true {
                let sent = Date()
                let signal = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { signal.signal() }

                // Wait out the threshold first. If the token comes back inside
                // it, nothing interesting happened.
                var stack: [UInt64] = []
                if signal.wait(timeout: .now() + threshold) == .timedOut {
                    // Still stuck — sample it *now*. Waiting for the token to
                    // arrive and sampling then would capture whatever the main
                    // thread moved on to, which is the one stack guaranteed not
                    // to be the culprit.
                    stack = sampleMainThread()

                    // Generous cap: the point is to measure long blocks, not to
                    // give up on them.
                    _ = signal.wait(timeout: .now() + 60)
                }

                let blocked = Date().timeIntervalSince(sent)

                if blocked > threshold {
                    // Only report a block that is worse than the last one, so a
                    // sustained freeze produces a few escalating lines rather
                    // than a wall of them.
                    if blocked > worstReported * 1.5 {
                        worstReported = blocked
                        AppLogger.log(tag: "Watchdog",
                                      "main thread blocked ~\(Int(blocked * 1000))ms")
                        report(stack)
                    }
                } else {
                    worstReported = 0
                }

                Thread.sleep(forTimeInterval: interval)
            }
        }
    }

    // MARK: - Sampling

    /// Suspends the main thread just long enough to copy its return addresses.
    ///
    /// The suspend window does no allocation, takes no locks and makes no
    /// Objective-C calls, because the suspended thread may be holding the very
    /// locks those need.
    private static func sampleMainThread() -> [UInt64] {
        let thread = mainThread
        guard thread != mach_port_t(MACH_PORT_NULL) else { return [] }
        guard thread_suspend(thread) == KERN_SUCCESS else { return [] }

        let depth = collectFrames(of: thread)
        thread_resume(thread)

        return (0..<depth).map { addresses[$0] }
    }

    /// Walks the frame-pointer chain, filling `addresses`. Returns the count.
    private static func collectFrames(of thread: thread_t) -> Int {
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)

        let ok = withUnsafeMutablePointer(to: &state) { pointer -> Bool in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64),
                                 $0, &count) == KERN_SUCCESS
            }
        }
        guard ok else { return 0 }

        var depth = 0
        addresses[depth] = strip(state.__pc)
        depth += 1

        // Each frame record is a pair: the caller's frame pointer, then the
        // return address. Walking stops on a null, unaligned or non-increasing
        // frame pointer — a corrupt chain must not send this into the weeds
        // while the main thread is suspended.
        var frame = UInt(strip(state.__fp))
        while depth < maximumFrames, frame != 0, frame % 8 == 0 {
            let record = UnsafeRawPointer(bitPattern: frame)?
                .assumingMemoryBound(to: UInt.self)
            guard let record else { break }

            let next = record[0]
            let returnAddress = UInt64(record[1])
            guard returnAddress != 0 else { break }

            addresses[depth] = strip(returnAddress)
            depth += 1

            // Stacks grow downwards, so a frame pointer that does not increase
            // means the chain is broken or looping.
            guard next > frame else { break }
            frame = next
        }
        return depth
    }

    /// Clears pointer-authentication bits. System frames on recent devices sign
    /// return addresses, and a signed pointer resolves to nothing.
    private static func strip(_ pointer: UInt64) -> UInt64 {
        pointer & 0x0000_000F_FFFF_FFFF
    }

    // MARK: - Symbolication

    /// Turns addresses into names. Runs after the resume, so it is free to
    /// allocate.
    private static func report(_ stack: [UInt64]) {
        guard !stack.isEmpty else {
            AppLogger.log(tag: "Watchdog", "  (no stack — main thread port not captured yet)")
            return
        }

        for (index, address) in stack.enumerated() {
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: UInt(address)), &info) != 0,
                  let rawName = info.dli_sname else {
                AppLogger.log(tag: "Watchdog",
                              String(format: "  %2d  0x%llx", index, address))
                continue
            }

            let symbol = String(cString: rawName)
            let image = info.dli_fname
                .map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
            AppLogger.log(tag: "Watchdog",
                          "  \(String(format: "%2d", index))  \(image)  \(demangled(symbol))")
        }
    }

    /// Swift symbols come back mangled. The runtime can undo that, and reaching
    /// for it directly avoids shipping a demangler.
    private static func demangled(_ symbol: String) -> String {
        guard symbol.hasPrefix("$s") || symbol.hasPrefix("_$s") else { return symbol }
        guard let handle = dlopen(nil, RTLD_NOW),
              let pointer = dlsym(handle, "swift_demangle") else { return symbol }

        typealias Demangle = @convention(c) (
            UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?,
            UnsafeMutablePointer<Int>?, UInt32
        ) -> UnsafeMutablePointer<CChar>?

        let demangle = unsafeBitCast(pointer, to: Demangle.self)
        guard let result = demangle(symbol, symbol.utf8.count, nil, nil, 0) else {
            return symbol
        }
        defer { result.deallocate() }
        return String(cString: result)
    }
}

#endif
