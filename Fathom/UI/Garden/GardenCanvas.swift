import SwiftUI

// MARK: - Canvas garden
//
// The whole year is drawn in a single immediate-mode `Canvas`: each unique
// doodle is pre-rendered once as a tinted symbol, then drawn many times as a
// dense, overlapping meadow. A single `reveal` value (0→1) animates a top-down
// "growth wave" — far cheaper and smoother than animating hundreds of views.

struct GardenCanvas: View {
    /// Reading time per day, aligned to Jan 1…Dec 31 (0 = no reading → a dot).
    let durations: [TimeInterval]
    let ink: Color
    let columns: Int
    /// When false (e.g. the year is hidden behind a restored month view), the
    /// bloom + haptics are skipped and the garden shows settled immediately.
    var animateBloom: Bool = true
    /// Called with the day index when a cell is tapped (for the future detail sheet).
    var onSelectDay: (Int) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The layout is resolved once into sprites; the per-frame draw loop only
    // applies the bloom envelope. The dot grid depends only on the day count, so
    // it's built immediately; the doodles are (re)built when the data arrives.
    @State private var dotSprites: [GardenSprite] = []
    @State private var doodleSprites: [GardenSprite] = []
    @State private var canvasSize: CGSize = .zero
    @State private var startDate = Date()
    @State private var revealComplete = false
    @State private var hasBloomed = false
    @State private var selectionTick = 0
    @State private var haptics = GardenHaptics()
    @State private var completionTask: Task<Void, Never>?

    private let revealDuration: Double = 2.5
    /// A held beat before the doodles start, so the dot grid registers first.
    private let bloomDelay: Double = 0.45

    /// Wall-clock length of the bloom — when the last doodle settles.
    private var visualDuration: Double {
        let ends = doodleSprites.map { min(1, $0.bloomStart + $0.bloomSpan) }
        guard let last = ends.max() else { return 0 }
        return revealDuration * last
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The static dot grid lives in its own symbol-less Canvas so it
                // paints on the very first frame — it never waits for the doodle
                // images to rasterize, and it never redraws during the bloom.
                Canvas { context, _ in drawDots(into: context) }

                // Doodles bloom on top. Canvas can't interpolate a withAnimation
                // value, so a per-frame clock drives it; cap the rate (~60fps) and
                // pause once the bloom finishes (or under Reduce Motion).
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: revealComplete || reduceMotion)) { timeline in
                    let reveal: Double = (revealComplete || reduceMotion)
                        ? 1
                        : clamp01((timeline.date.timeIntervalSince(startDate) - bloomDelay) / revealDuration)

                    Canvas { context, _ in
                        drawDoodles(into: context, reveal: reveal)
                    } symbols: {
                        ForEach(DoodleCatalog.allAssetNames, id: \.self) { name in
                            symbol(for: name)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let index = hitTest(value.location) {
                        selectionTick &+= 1
                        onSelectDay(index)
                    }
                }
            )
            // The dot grid is built immediately (data-independent); the doodle
            // bloom (re)starts on appear and on each data change. `startDate` is set
            // synchronously so the timeline never reads a stale, saturated value.
            // Bloom on first appear and on each data change. A pure size change
            // (e.g. device rotation) only relayouts — it must NOT replay the
            // animation or haptics, so it animates only if we never bloomed yet.
            .onAppear { rebuild(size: geo.size, animate: !hasBloomed) }
            .onChange(of: geo.size) { _, newSize in rebuild(size: newSize, animate: !hasBloomed) }
            .onChange(of: durations) { _, _ in rebuild(size: geo.size, animate: true) }
        }
        // Modern selection feedback (replaces a manual UIImpactFeedbackGenerator).
        .sensoryFeedback(.selection, trigger: selectionTick)
        .onDisappear {
            completionTask?.cancel()
            haptics.stop()
        }
    }

    /// Rebuild the dot grid (always) and the doodles. When `animate` is true the
    /// bloom (re)starts; when false (a relayout such as rotation) the final state
    /// is shown immediately with no animation or haptics.
    private func rebuild(size: CGSize, animate: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        canvasSize = size
        // Dots first — they paint immediately, even before any reading data loads.
        dotSprites = buildDotGrid(count: durations.count, size: size, columns: columns)
        doodleSprites = buildDoodleSprites(durations: durations, size: size, columns: columns)
        completionTask?.cancel()

        // No bloom: a non-animating relayout, the year isn't the active view,
        // nothing to show yet (loading / empty), or Reduce Motion → jump straight
        // to the settled state.
        guard animate, animateBloom, !doodleSprites.isEmpty, !reduceMotion else {
            revealComplete = true
            return
        }

        hasBloomed = true
        startDate = Date()
        revealComplete = false

        let dur = visualDuration
        // Fire one soft tick per doodle as it pops in — derived from the exact
        // bloom times so the haptics track the visual cascade instead of running
        // on their own clock. Skipped in Low Power Mode to avoid the engine spin-up.
        if dur > 0, !ProcessInfo.processInfo.isLowPowerModeEnabled {
            let (times, strengths) = hapticTicks()
            haptics.playTicks(times: times, strengths: strengths)
        }
        // Pause the timeline precisely when the bloom ends (after the held beat).
        // Cancellable so a new bloom (or leaving the view) never flips stale state.
        completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((bloomDelay + dur + 0.15) * 1_000_000_000))
            if !Task.isCancelled { revealComplete = true }
        }
    }

    /// A tinted doodle, with the dark-mode glow *baked into the symbol* so it is
    /// rasterized once — instead of a per-frame, per-doodle shadow filter (the
    /// old hot path). The padding gives the blur room so it isn't clipped.
    @ViewBuilder
    private func symbol(for name: String) -> some View {
        let image = Image(name).renderingMode(.template).resizable().foregroundStyle(ink)
        if colorScheme == .dark {
            image.shadow(color: ink.opacity(0.5), radius: 3).padding(4).tag(name)
        } else {
            image.tag(name)
        }
    }

    // MARK: Drawing

    /// The static dot grid — every day, fully present from the first frame.
    private func drawDots(into context: GraphicsContext) {
        for sprite in dotSprites {
            guard case .dot(let r, let opacity) = sprite.kind else { continue }
            let p = sprite.center
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                with: .color(ink.opacity(opacity))
            )
        }
    }

    /// The doodles — blank until each one's turn, then a staggered top-down pop
    /// that grows over the dot already sitting at that cell.
    private func drawDoodles(into context: GraphicsContext, reveal: Double) {
        for sprite in doodleSprites {
            guard case .doodle(let id, _) = sprite.kind else { continue }
            let local = clamp01((reveal - sprite.bloomStart) / sprite.bloomSpan)
            if local <= 0 { continue }
            guard let symbol = context.resolveSymbol(id: id) else { continue }
            let opacity = 1 - pow(1 - local, 3)               // easeOutCubic fade
            let dim = sprite.baseDim * CGFloat(0.4 + 0.6 * easeOutBack(local))  // subtle overshoot
            context.drawLayer { layer in
                layer.opacity = opacity
                layer.translateBy(x: sprite.center.x, y: sprite.center.y)
                layer.draw(symbol, in: CGRect(x: -dim / 2, y: -dim / 2, width: dim, height: dim))
            }
        }
    }

    // MARK: Haptic ticks

    /// One tick per doodle, timed to when it becomes *visibly* present (a little
    /// after its bloom starts, since the ease keeps it faint at first). Ticks
    /// landing within a few ms are merged so dense rows feel like one firmer
    /// beat instead of an indistinct buzz.
    private func hapticTicks() -> (times: [Double], strengths: [Float]) {
        // A doodle reads as "there" partway through its bloom, not at its start.
        let visibleAt = 0.35
        let mergeGap = 0.03

        let raw: [(t: Double, s: Float)] = doodleSprites.compactMap { sp in
            guard case .doodle(_, let strength) = sp.kind else { return nil }
            // Offset by the held beat so the first tick lands with the first doodle.
            let t = bloomDelay + (sp.bloomStart + sp.bloomSpan * visibleAt) * revealDuration
            return (t, strength)
        }
        .sorted { $0.t < $1.t }

        var times: [Double] = []
        var strengths: [Float] = []
        for ev in raw {
            if let last = times.last, ev.t - last < mergeGap {
                strengths[strengths.count - 1] = max(strengths[strengths.count - 1], ev.s)
            } else {
                times.append(ev.t)
                strengths.append(ev.s)
            }
        }
        return (times, strengths)
    }

    // MARK: Hit testing

    /// Nearest doodle whose radius covers the tap (doodles are what's meaningful
    /// to select), falling back to the plain grid cell for empty days.
    private func hitTest(_ point: CGPoint) -> Int? {
        var best: Int?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for s in doodleSprites {
            let dx = s.center.x - point.x, dy = s.center.y - point.y
            let d2 = dx * dx + dy * dy
            if d2 <= s.radius * s.radius, d2 < bestDist { bestDist = d2; best = s.dayIndex }
        }
        return best ?? GardenLayout.cell(
            at: point, count: durations.count, size: canvasSize, columns: columns)
    }
}

/// easeOutBack — rises past 1 then settles back to 1, giving a gentle pop.
private func easeOutBack(_ t: Double) -> Double {
    let c1 = 1.70158, c3 = 1.70158 + 1
    let p = t - 1
    return 1 + c3 * p * p * p + c1 * p * p
}
