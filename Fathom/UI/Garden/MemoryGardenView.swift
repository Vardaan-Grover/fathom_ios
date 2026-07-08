import SwiftUI
import UIKit
import CoreHaptics

private struct PopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        DispatchQueue.main.async {
            vc.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            vc.navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

struct MemoryGardenView: View {
    @StateObject private var viewModel: MemoryGardenViewModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Environment(\.colorScheme) private var colorScheme

    /// The sky's one dominant hue — a deep, bright blue used for both the
    /// doodles and the empty-day dots (a touch brighter on the dark background).
    private var ink: Color {
        let base = Color(hex: "1530E6")  // deep bright blue
        return colorScheme == .dark
            ? base.adjusted(saturationScale: 1.0, brightnessDelta: 0.12)
            : base
    }

    let year: Int
    let daysInYear: [Date]
    /// When set, the garden opens into the reveal ceremony for this doodle/day.
    let revealRequest: RevealRequest?

    init(
        year: Int = Calendar.current.component(.year, from: Date()),
        bookRepository: BookRepository,
        revealRequest: RevealRequest? = nil
    ) {
        self.year = year
        self.revealRequest = revealRequest
        self._viewModel = StateObject(
            wrappedValue: MemoryGardenViewModel(bookRepository: bookRepository))

        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        // Use the real day count so leap years keep Dec 31 and day→date stays aligned.
        let dayCount = calendar.range(of: .day, in: .year, for: startOfYear)?.count ?? 365
        let days = (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startOfYear)
        }
        self.daysInYear = days
    }

    // The whole year on one screen, tightly packed like One Year — the Canvas
    // sizes cells from the available space so all 365 days fit without scrolling.
    private let columnCount = 14

    /// The day whose detail sheet is open.
    @State private var selectedDay: SelectedDay?
    private struct SelectedDay: Identifiable {
        let id: String        // the "yyyy-MM-dd" key
        let date: Date
        let dayOfYear: Int    // 1-based, so the sheet's doodle matches the grid
    }

    private enum ViewMode: String { case year, month }
    /// Persisted so reopening the screen restores the last view (year or month).
    @AppStorage("memoryGarden.viewMode") private var mode: ViewMode = .year
    @State private var currentMonth = Calendar.current.component(.month, from: Date())

    // Pinch-zoom transition between year (t=0) and month (t=1).
    @State private var zoomT: CGFloat = 0
    @State private var zoomAnchor: UnitPoint = .center
    @State private var hasZoomed = false
    /// Bumped exactly once, the first time we land in a month, so the month view
    /// blooms in only on its initial appearance (not on every zoom-in).
    @State private var monthRevealTrigger = 0
    @State private var monthHasBloomed = false

    // Reveal ceremony state.
    @Namespace private var heroNS
    private enum RevealStage { case none, frosted, unveiled, landed }
    @State private var revealStage: RevealStage = .none
    @State private var revealDay: Date?
    /// True while a pinch is in flight — suspends cell taps so a pinch over the
    /// calendar can't be mistaken for a day selection.
    @State private var isZooming = false

    /// Open the detail sheet for a date (used by both the year and month views).
    private func select(_ date: Date, dayOfYear: Int) {
        selectedDay = SelectedDay(
            id: Self.dayKeyFormatter.string(from: date), date: date, dayOfYear: dayOfYear)
    }

    // MARK: Header

    /// One adaptive bar: close on the left, dice on the right, and a single
    /// contextual title in the middle — the year badge in year view, or the
    /// month stepper in month view (no more duplicated year + month labels).
    private var header: some View {
        ZStack {
            Group {
                if mode == .month {
                    HStack(spacing: 10) {
                        headerChevron("chevron.left", enabled: currentMonth > 1) { stepMonth(-1) }
                        Text(monthLabelDate, format: .dateTime.month(.wide).year())
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundColor(theme.colors.primary)
                            .frame(minWidth: 152)
                        headerChevron("chevron.right", enabled: currentMonth < 12) { stepMonth(1) }
                    }
                } else {
                    Text(String(year))
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundColor(theme.colors.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(ink)
                        .clipShape(Capsule())
                }
            }
            .transition(.opacity)

            HStack {
                headerIcon("xmark") { dismiss() }
                Spacer(minLength: 0)
                #if DEBUG
                HStack(spacing: 8) {
                    // Dev-only: wipe all reading data (so you can test "spotting").
                    headerIcon("trash") { Task { await viewModel.clearMockData(year: year) } }
                    // Dev-only: seed randomized mock data (clears the year first).
                    headerIcon("dice") { Task { await viewModel.injectDenseMockData(year: year) } }
                }
                #endif
            }
            .padding(.horizontal, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private func headerIcon(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ink.opacity(colorScheme == .dark ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    private func headerChevron(_ system: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(ink.opacity(colorScheme == .dark ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.25)
        .disabled(!enabled)
    }

    private var monthLabelDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: currentMonth, day: 1)) ?? Date()
    }

    private func stepMonth(_ delta: Int) {
        let next = currentMonth + delta
        guard (1...12).contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentMonth = next }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                header
                    .padding(.top, 14)

                Text(mode == .year ? "Pinch to open a month" : "Pinch to step back")
                    .font(.caption2)
                    .foregroundColor(theme.colors.secondary)
                    .opacity((hasZoomed || revealRequest != nil) ? 0 : 0.6)
                    .animation(.easeInOut, value: hasZoomed)

                zoomContainer
            }

            if revealStage != .none, let req = revealRequest {
                RevealOverlay(
                    request: req,
                    ink: ink,
                    heroNamespace: heroNS,
                    isFrosted: revealStage == .frosted,
                    isLeaving: revealStage == .landed,
                    onUnveil: unveil,
                    onLand: land,
                    onSkip: skip
                )
            }
        }
        .navigationBarBackButtonHidden()
        .background(theme.colors.background.ignoresSafeArea())
        .background(PopGestureEnabler())
        .sheet(item: $selectedDay) { selection in
            DayDetailSheet(
                date: selection.date,
                dayOfYear: selection.dayOfYear,
                activity: viewModel.dailyActivities[selection.id],
                books: viewModel.loadedBooks,
                ink: ink
            )
        }
        .onAppear {
            if let req = revealRequest {
                // Open straight into the doodle's month, behind the ceremony.
                mode = .month
                currentMonth = Calendar.current.component(.month, from: req.date)
                monthHasBloomed = true
                zoomT = 1
                revealDay = req.date
                revealStage = .frosted
            } else {
                zoomT = (mode == .month) ? 1 : 0
            }
            Task {
                await viewModel.load(forYear: year)
                // Bloom the month in once data is present. In the reveal flow this
                // brings the *other* days in behind the frosted glass (the reveal
                // day is suppressed) and leaves revealProgress at 1 so its doodle
                // stays visible after it lands.
                if revealRequest != nil || (mode == .month && !monthHasBloomed) {
                    monthHasBloomed = true
                    monthRevealTrigger &+= 1
                }
            }
        }
    }

    // MARK: Reveal flow

    private func unveil() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { revealStage = .unveiled }
    }

    private func land() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        // Flip the hero from the card to the real cell: removing the overlay hero
        // and adding the cell hero animates the flight via matchedGeometryEffect.
        withAnimation(.spring(response: 0.6, dampingFraction: 0.74)) {
            revealStage = .landed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            // Hand the cell back to its normal (non-hero) doodle, seamlessly.
            revealStage = .none
            revealDay = nil
        }
    }

    /// Dismiss the ceremony without the flight — the doodle just appears settled.
    private func skip() {
        withAnimation(.easeOut(duration: 0.3)) {
            revealStage = .none
            revealDay = nil
        }
    }

    /// The reveal day's cell shows the hero only after the flight begins.
    private var revealLanded: Bool { revealStage == .landed }

    /// Both views stacked, cross-faded and scaled by the pinch (`zoomT`). Only
    /// the layer(s) actually visible are kept in the tree, so pure year/month
    /// rest states pay for one view, not two.
    private var zoomContainer: some View {
        GeometryReader { _ in
            ZStack {
                // Always mounted so zooming out never re-creates it (which would
                // reset its state and replay the whole bloom, flashing blank).
                yearGarden
                    .scaleEffect(1 + zoomT * 0.5, anchor: zoomAnchor)
                    .opacity(Double(1 - zoomT))
                    .allowsHitTesting(mode == .year)

                // Also always mounted, so its one-time bloom state survives and
                // it never re-blooms on a later zoom-in.
                MonthGardenView(
                    year: year,
                    month: $currentMonth,
                    activities: viewModel.dailyActivities,
                    ink: ink,
                    revealTrigger: monthRevealTrigger,
                    onSelectDate: { date in
                        let doy = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
                        select(date, dayOfYear: doy)
                    },
                    heroNamespace: heroNS,
                    revealDay: revealDay,
                    revealLanded: revealLanded
                )
                .scaleEffect(0.92 + zoomT * 0.08, anchor: zoomAnchor)
                .opacity(Double(zoomT))
                .allowsHitTesting(mode == .month && !isZooming)
                .padding(.bottom, 90)  // clear the floating tab bar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // High priority so a two-finger pinch wins over the day-cell buttons
            // (a one-finger tap needs no magnification, so taps still pass through).
            .highPriorityGesture(zoomGesture())
        }
    }

    /// Pinch open on the year to dive into the month under your fingers; pinch
    /// closed in a month to step back out. Live scale/opacity track the pinch,
    /// then snap to the nearer end on release.
    private func zoomGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isZooming = true
                zoomAnchor = value.startAnchor
                switch mode {
                case .year:
                    // Always land in the present month, regardless of where the
                    // pinch is on the year grid.
                    currentMonth = Calendar.current.component(.month, from: Date())
                    zoomT = CGFloat(clamp01((Double(value.magnification) - 1) / 0.8))
                case .month:
                    zoomT = CGFloat(1 - clamp01((1 - Double(value.magnification)) / 0.5))
                }
            }
            .onEnded { _ in
                hasZoomed = true
                let toMonth = zoomT >= 0.5
                mode = toMonth ? .month : .year
                // Bloom the month in only on its very first appearance.
                if toMonth, !monthHasBloomed {
                    monthHasBloomed = true
                    monthRevealTrigger &+= 1
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                    zoomT = toMonth ? 1 : 0
                }
                // Keep taps suspended a beat so the pinch's release can't land
                // on a cell, then re-enable selection.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    isZooming = false
                }
            }
    }

    /// The dense, full-year Canvas garden (with the bloom + the dev seed button).
    private var yearGarden: some View {
        // The garden is always on screen so the dot grid paints immediately —
        // durations are all-zero until data loads (dots only), then fill in and
        // the doodles bloom. Aligned once per data change, so the Canvas never
        // touches a DateFormatter or dictionary mid-frame.
        // "Forms today, settles tomorrow": a day only earns a *visible* doodle once
        // it's complete. Today (and any future day) stays a dot — its doodle is
        // still being spotted and is revealed the next day.
        let todayStart = Calendar.current.startOfDay(for: Date())
        let durations = daysInYear.map { date -> TimeInterval in
            guard date < todayStart else { return 0 }
            return viewModel.dailyActivities[Self.dayKeyFormatter.string(from: date)]?.duration ?? 0
        }
        return GardenCanvas(
            durations: durations, ink: ink, columns: columnCount,
            animateBloom: mode == .year   // stay silent if restored into month view
        ) { index in
            // Open the day-detail sheet. (Selection haptic is inside GardenCanvas.)
            select(daysInYear[index], dayOfYear: index + 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 90)  // clear the floating tab bar
        .overlay {
            // Once loaded with no reading at all, offer the dev seed button.
            if !viewModel.isLoading, viewModel.dailyActivities.isEmpty {
                Button("Plant Some Seeds (Mock Data)") {
                    Task { await viewModel.injectMockData(year: year) }
                }
                .font(.subheadline)
                .foregroundColor(theme.colors.shelfAccent)
            }
        }
    }

    /// One cached formatter for the "yyyy-MM-dd" activity keys — building a
    /// DateFormatter is costly, and this is hit once per day in the year.
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

}

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

private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

/// easeOutBack — rises past 1 then settles back to 1, giving a gentle pop.
private func easeOutBack(_ t: Double) -> Double {
    let c1 = 1.70158, c3 = 1.70158 + 1
    let p = t - 1
    return 1 + c3 * p * p * p + c1 * p * p
}

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
