import SwiftUI

/// A single month of the garden as a true S–M–T–W–T–F–S calendar. The doodles
/// are large and legible here (vs the dense year view), each day is tappable to
/// open its detail sheet, and the binding stays within the loaded year.
///
/// When you land in a month (or change months) the doodles bloom in with a soft
/// staggered reveal + matching haptics — `revealTrigger` is bumped by the parent
/// on arrival; internal navigation re-fires it itself.
struct MonthGardenView: View {
    let year: Int
    @Binding var month: Int
    let activities: [String: DailyActivity]
    let ink: Color
    let revealTrigger: Int
    var onSelectDate: (Date) -> Void

    // Reveal-ceremony hand-off: the doodle for `revealDay` is suppressed until
    // `revealLanded`, then drawn as the shared hero so the ceremony can fly it
    // into this exact cell.
    var heroNamespace: Namespace.ID? = nil
    var revealDay: Date? = nil
    var revealLanded: Bool = false

    // Backfill: "remembered" nights render ghosted; `backfillMode` shows their
    // placeholders as inviting slots (handled by the caller's tap routing).
    var remembered: Set<String> = []
    var backfillMode: Bool = false

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var haptics = GardenHaptics()

    private let revealDuration: Double = 1.0
    private let cellWindow: Double = 0.5

    private let calendar = Calendar.current
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private static let key: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(spacing: 14) {
            weekdayHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, date in
                    if let date {
                        let key = Self.key.string(from: date)
                        let duration = activities[key]?.duration ?? 0
                        let tracked = settledDoodle(for: date, duration: duration)
                        let isRemembered = tracked == nil
                            && remembered.contains(key)
                            && date < calendar.startOfDay(for: Date())
                        let doodle = tracked ?? (isRemembered ? rememberedDoodle(for: date) : nil)
                        let isReveal = revealDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false

                        MonthDayCell(
                            date: date,
                            index: index,
                            totalCells: cells.count,
                            duration: duration,
                            doodleName: doodle,
                            ghosted: isRemembered,
                            isReveal: isReveal,
                            revealLanded: revealLanded,
                            ink: ink,
                            onSelect: { onSelectDate(date) },
                            heroNamespace: heroNamespace
                        )
                        .id("\(revealTrigger)-\(index)")
                    } else {
                        Color.clear.frame(height: 62)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -40 { step(1) } else if value.translation.width > 40 { step(-1) }
                }
        )
        .onChange(of: revealTrigger) { _, _ in playReveal() }
        .onDisappear { haptics.stop() }
    }

    // MARK: Header

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundColor(theme.colors.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Reveal

    /// Restart the staggered bloom and fire one soft tick per doodle as it lands.
    private func playReveal() {
        guard !reduceMotion else { return }

        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        var times: [Double] = []
        var strengths: [Float] = []
        for (i, date) in cells.enumerated() {
            guard let date else { continue }
            let key = Self.key.string(from: date)
            let duration = activities[key]?.duration ?? 0
            guard settledDoodle(for: date, duration: duration) != nil else { continue }
            let start = Double(i) / Double(max(1, cells.count)) * (1 - cellWindow)
            times.append(start * revealDuration + 0.04)
            strengths.append(tickStrength(for: duration))
        }
        if !times.isEmpty { haptics.playTicks(times: times, strengths: strengths) }
    }

    private func tickStrength(for duration: TimeInterval) -> Float {
        switch DoodleTier.tier(for: duration) {
        case .glimpse:    return 0.45
        case .settledIn:  return 0.7
        case .grandNight: return 1.0
        case .none:       return 0.4
        }
    }

    /// A day's doodle, but only once the day is complete ("forms today, settles
    /// tomorrow"). Today and future days return nil → they stay dots.
    private func settledDoodle(for date: Date, duration: TimeInterval) -> String? {
        guard date < calendar.startOfDay(for: Date()) else { return nil }
        let doy = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return DoodleCatalog.assetName(forDayOfYear: doy, duration: duration)
    }

    /// The doodle for a backfilled "remembered" night (deterministic pseudo-tier).
    private func rememberedDoodle(for date: Date) -> String? {
        let doy = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return DoodleCatalog.assetName(forDayOfYear: doy, duration: RememberedNights.duration(forDayOfYear: doy))
    }

    // MARK: Calendar math

    private var startOfMonth: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
    }

    /// Leading empty slots so day 1 lands under its weekday (Sunday-first).
    private var leadingBlanks: Int {
        calendar.component(.weekday, from: startOfMonth) - 1
    }

    private var cells: [Date?] {
        let blanks = [Date?](repeating: nil, count: leadingBlanks)
        let days: [Date?] = (0..<daysInMonth).map {
            calendar.date(byAdding: .day, value: $0, to: startOfMonth)
        }
        return blanks + days
    }

    private func step(_ delta: Int) {
        let next = month + delta
        guard (1...12).contains(next) else { return }
        // Navigating months doesn't re-bloom — the reveal is a one-time arrival
        // moment. The new month's doodles are simply shown.
        withAnimation(.easeInOut(duration: 0.2)) { month = next }
    }
}

// MARK: - MonthDayCell

struct MonthDayCell: View {
    let date: Date
    let index: Int
    let totalCells: Int
    let duration: TimeInterval
    let doodleName: String?
    var ghosted: Bool = false
    let isReveal: Bool
    let revealLanded: Bool
    let ink: Color
    let onSelect: () -> Void
    let heroNamespace: Namespace.ID?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isVisible: Bool = false

    var body: some View {
        let dayNum = Calendar.current.component(.day, from: date)
        let today = Calendar.current.isDateInToday(date)
        let shownDoodle = isReveal ? (revealLanded ? doodleName : nil) : doodleName

        Button {
            onSelect()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if let shownDoodle {
                        Image(shownDoodle)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(ink)
                            .frame(height: 38)
                            // Soft two-layer glow (gentler on light paper).
                            .shadow(color: ink.opacity(colorScheme == .dark ? 0.6 : 0.3), radius: 4)
                            .shadow(color: ink.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 9)
                            .padding(14) // Give the shadows enough room so they don't get clipped by drawingGroup
                            .drawingGroup()
                            .padding(-14) // Negate the padding to keep original layout bounds
                            .opacity(ghosted ? 0.4 : 1)   // ghost a remembered night
                            .modifier(RevealCellModifier(
                                isHero: isReveal && revealLanded,
                                namespace: heroNamespace,
                                isVisible: isVisible
                            ))
                    } else {
                        Circle()
                            .fill(ink.opacity(0.16))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 40)

                Text("\(dayNum)")
                    .font(.system(size: 10, weight: today ? .bold : .medium, design: .serif))
                    .foregroundColor(today ? theme.colors.background : (shownDoodle != nil ? ink.opacity(0.75) : theme.colors.secondary.opacity(0.6)))
                    .frame(width: 18, height: 16)
                    .background(today ? Circle().fill(ink).frame(width: 18, height: 18) : nil)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            triggerAnimation()
        }
    }

    private func triggerAnimation() {
        if reduceMotion {
            isVisible = true
            return
        }
        isVisible = false
        // Staggered delay based on cell index.
        let cellWindow = 0.5
        let startDelay = (Double(index) / Double(max(1, totalCells))) * (1.0 - cellWindow)
        withAnimation(.easeOut(duration: 0.5).delay(startDelay)) {
            isVisible = true
        }
    }
}

/// Either the shared reveal hero (the ceremony flies the doodle into this cell)
/// or the normal staggered bloom — never both.
private struct RevealCellModifier: ViewModifier {
    let isHero: Bool
    let namespace: Namespace.ID?
    let isVisible: Bool

    func body(content: Content) -> some View {
        if isHero, let namespace {
            content.matchedGeometryEffect(id: "revealHero", in: namespace)
        } else {
            content
                .scaleEffect(isVisible ? 1.0 : 0.5)
                .opacity(isVisible ? 1.0 : 0.0)
        }
    }
}
