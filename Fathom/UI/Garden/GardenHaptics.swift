import CoreHaptics

// MARK: - Garden haptics
//
// One soft tick per doodle, fired at the exact moment it pops into view. The
// caller hands us the bloom times + per-doodle strengths it already computed, so
// the haptics are *the same data as the animation* — they can't drift out of
// sync. One cached engine plays the whole sequence as a single pattern.

@MainActor
final class GardenHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// Plays a soft "puff" at each `times[i]` with intensity `strengths[i]`.
    /// Times are relative seconds from now, matching the doodles' appearance.
    /// Each puff is a short *continuous* event with near-zero sharpness and a
    /// gentle attack/decay, so it feels diffuse and blurry rather than a sharp
    /// click; overlapping puffs in dense rows blend into a soft swell.
    func playTicks(times: [Double], strengths: [Float]) {
        guard supportsHaptics, !times.isEmpty else { return }
        do {
            let engine = try ensureEngine()
            let events = zip(times, strengths).map { time, strength in
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: strength * 0.85),
                        // Near-zero sharpness = a dull, rounded thump, not a tick.
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.02),
                        // Ease in and out so there's no hard onset edge.
                        CHHapticEventParameter(parameterID: .attackTime, value: 0.04),
                        CHHapticEventParameter(parameterID: .decayTime, value: 0.14),
                        CHHapticEventParameter(parameterID: .releaseTime, value: 0.12),
                        CHHapticEventParameter(parameterID: .sustained, value: 0),
                    ],
                    relativeTime: max(0, time),
                    duration: 0.16
                )
            }
            let player = try engine.makePlayer(with: try CHHapticPattern(events: events, parameters: []))
            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptics are a nicety — a failure must never affect the UI.
        }
    }

    /// Cut the haptic immediately (the player, not the engine — so the engine
    /// stays warm for the next bloom and there's no async stop tail).
    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    private func ensureEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let engine = try CHHapticEngine()
        // Power-friendly: the engine sleeps when idle and restarts lazily.
        engine.isAutoShutdownEnabled = true
        engine.stoppedHandler = { [weak self] _ in self?.engine = nil }
        engine.resetHandler = { [weak self] in try? self?.engine?.start() }
        try engine.start()
        self.engine = engine
        return engine
    }
}
