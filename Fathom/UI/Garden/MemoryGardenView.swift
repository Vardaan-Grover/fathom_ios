import SwiftUI
import UIKit

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
    private var ink: Color { .gardenInk(colorScheme) }

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

    @State private var showShare = false
    @State private var showRevealShare = false

    // Backfill: mark past nights you read before Fathom (ghosted, visual-only).
    @State private var remembered: Set<String> = RememberedNights.load()
    @State private var backfillMode = false

    /// Toggle a past, untracked day as a "remembered" night.
    private func toggleRemembered(_ date: Date) {
        guard date < Calendar.current.startOfDay(for: Date()) else { return }  // past only
        let key = Self.dayKeyFormatter.string(from: date)
        // Never overwrite a real tracked night.
        guard (viewModel.dailyActivities[key]?.duration ?? 0) == 0 else { return }
        if remembered.contains(key) { remembered.remove(key) } else { remembered.insert(key) }
        RememberedNights.save(remembered)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Nights read + hours for the currently-shown month (settled nights only).
    private func monthShareStats() -> (nights: Int, hours: String) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var nights = 0
        var seconds: TimeInterval = 0
        for (_, activity) in viewModel.dailyActivities where activity.duration > 0 {
            let c = cal.dateComponents([.year, .month], from: activity.date)
            guard c.year == year, c.month == currentMonth else { continue }
            seconds += activity.duration
            if activity.date < todayStart { nights += 1 }
        }
        let h = seconds / 3600
        return (nights, h >= 1 ? String(Int(h.rounded())) : "<1")
    }

    /// The book that most of a day's reading came from (for the reveal share card).
    private func revealMajorBook(for date: Date) -> Book? {
        let key = Self.dayKeyFormatter.string(from: date)
        guard let activity = viewModel.dailyActivities[key] else { return nil }
        let majorID = activity.bookDurations.max(by: { $0.value < $1.value })?.key
        return majorID.flatMap { viewModel.loadedBooks[$0] }
    }
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
                HStack(spacing: 8) {
                    headerIcon(backfillMode ? "checkmark" : "wand.and.stars") {
                        withAnimation(.easeInOut(duration: 0.2)) { backfillMode.toggle() }
                    }
                    headerIcon("square.and.arrow.up") { showShare = true }
                    #if DEBUG
                    // Dev-only: wipe all reading data (so you can test "spotting").
                    headerIcon("trash") { Task { await viewModel.clearMockData(year: year) } }
                    // Dev-only: seed randomized mock data (clears the year first).
                    headerIcon("dice") { Task { await viewModel.injectDenseMockData(year: year) } }
                    #endif
                }
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

                if backfillMode {
                    Text("Tap the nights you read before Fathom")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(ink.opacity(colorScheme == .dark ? 0.16 : 0.08)))
                        .transition(.opacity)
                } else {
                    Text(mode == .year ? "Pinch to open a month" : "Pinch to step back")
                        .font(.caption2)
                        .foregroundColor(theme.colors.secondary)
                        .opacity((hasZoomed || revealRequest != nil) ? 0 : 0.6)
                        .animation(.easeInOut, value: hasZoomed)
                }

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
                    onSkip: skip,
                    onShare: { showRevealShare = true }
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
        .sheet(isPresented: $showShare) {
            if mode == .month {
                let s = monthShareStats()
                MonthSharePreviewSheet(
                    year: year,
                    month: currentMonth,
                    name: UserProfileStore.shared.load().displayName ?? "",
                    nights: s.nights,
                    hours: s.hours,
                    activities: viewModel.dailyActivities,
                    theme: shareTheme,
                    defaultLine: "a month of looking up"
                )
            } else {
                ShareCardPreviewSheet(
                    year: year,
                    name: UserProfileStore.shared.load().displayName ?? "",
                    stats: ShareStats.forYear(year, activities: viewModel.dailyActivities, books: viewModel.loadedBooks),
                    durations: shareDurations,
                    columns: columnCount,
                    theme: shareTheme,
                    defaultLine: "a year of looking up"
                )
            }
        }
        .sheet(isPresented: $showRevealShare) {
            if let req = revealRequest {
                DoodleSharePreviewSheet(
                    doodleName: req.doodleName,
                    phrase: DoodleCatalog.phrase(for: req.doodleName),
                    date: req.date,
                    name: UserProfileStore.shared.load().displayName ?? "",
                    book: revealMajorBook(for: req.date),
                    theme: shareTheme
                )
            }
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
                        if backfillMode {
                            toggleRemembered(date)
                        } else {
                            let doy = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
                            select(date, dayOfYear: doy)
                        }
                    },
                    heroNamespace: heroNS,
                    revealDay: revealDay,
                    revealLanded: revealLanded,
                    remembered: remembered,
                    backfillMode: backfillMode
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
        // Each day is either tracked (solid), remembered/backfilled (ghosted), or empty.
        let dayData: [(duration: TimeInterval, remembered: Bool)] = daysInYear.enumerated().map { i, date in
            guard date < todayStart else { return (0, false) }
            let key = Self.dayKeyFormatter.string(from: date)
            if let tracked = viewModel.dailyActivities[key]?.duration, tracked > 0 {
                return (tracked, false)
            }
            if remembered.contains(key) {
                return (RememberedNights.duration(forDayOfYear: i + 1), true)
            }
            return (0, false)
        }
        return GardenCanvas(
            durations: dayData.map(\.duration), ink: ink, columns: columnCount,
            remembered: dayData.map(\.remembered),
            animateBloom: mode == .year   // stay silent if restored into month view
        ) { index in
            if backfillMode {
                toggleRemembered(daysInYear[index])
            } else {
                // Open the day-detail sheet. (Selection haptic is inside GardenCanvas.)
                select(daysInYear[index], dayOfYear: index + 1)
            }
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

    // MARK: Share

    /// Settled per-day durations for the share card (today/future stay dots).
    private var shareDurations: [TimeInterval] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return daysInYear.map { date in
            guard date < todayStart else { return 0 }
            return viewModel.dailyActivities[Self.dayKeyFormatter.string(from: date)]?.duration ?? 0
        }
    }

    /// The app theme's colors resolved to concrete values for the share renderer
    /// (which has no `@Environment`).
    private var shareTheme: ShareCardTheme {
        ShareCardTheme.resolved(
            background: theme.colors.background,
            ink: ink,   // the one garden ink — consistent everywhere
            primary: theme.colors.primary,
            secondary: theme.colors.secondary,
            scheme: colorScheme
        )
    }
}
