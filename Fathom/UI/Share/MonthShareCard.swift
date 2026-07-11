import SwiftUI

/// A share card for a single month: the calendar of doodles, month/year title,
/// this month's stats, and an editable note. Theme-matched; story + square.
struct MonthShareCardView: View {
    let year: Int
    let month: Int
    let name: String
    let line: String
    let nights: Int
    let hours: String
    let activities: [String: DailyActivity]
    let theme: ShareCardTheme
    let format: ShareCardFormat

    private var story: Bool { format == .story }

    private var monthTitle: String {
        let comps = DateComponents(year: year, month: month, day: 1)
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(name.isEmpty ? "A MONTH IN THE SKY" : "\(name.uppercased())’S SKY")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(theme.secondary)
                Text(monthTitle)
                    .font(.system(size: story ? 40 : 34, weight: .bold, design: .serif))
                    .foregroundStyle(theme.primary)
            }
            .padding(.top, story ? 52 : 34)
            .padding(.horizontal, 30)

            Spacer(minLength: 0)

            MonthGridStatic(year: year, month: month, activities: activities,
                            ink: theme.ink, secondary: theme.secondary)
                .frame(height: gridHeight)
                .padding(.horizontal, 28)

            statsRow
                .padding(.horizontal, 50)
                .padding(.top, story ? 26 : 16)

            if !line.isEmpty {
                Text(line)
                    .font(.custom("Reenie Beanie", size: story ? 40 : 30))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, story ? 24 : 12)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 0)

            Text("made with Fathom ✦")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .tracking(0.5)
                .foregroundStyle(theme.secondary)
                .padding(.bottom, story ? 46 : 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    /// The month's week-rows × a per-format cell size — so the grid is sized to
    /// its content (not stretched), and the leftover space is split evenly above
    /// and below by the surrounding spacers.
    private var weekRows: Int {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let blanks = cal.component(.weekday, from: start) - 1
        return max(1, Int(ceil(Double(blanks + days) / 7.0)))
    }
    private var gridHeight: CGFloat {
        CGFloat(weekRows) * (story ? 96 : 44) + 38   // + weekday header & spacing
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("\(nights)", nights == 1 ? "night read" : "nights read")
            Rectangle().fill(theme.secondary.opacity(0.25)).frame(width: 1, height: 28)
            stat(hours, "hours")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(theme.ink)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .tracking(1)
                .foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Preview + share for the month card.
struct MonthSharePreviewSheet: View {
    let year: Int
    let month: Int
    let name: String
    let nights: Int
    let hours: String
    let activities: [String: DailyActivity]
    let theme: ShareCardTheme
    let defaultLine: String

    @State private var line: String
    @FocusState private var focused: Bool

    init(year: Int, month: Int, name: String, nights: Int, hours: String,
         activities: [String: DailyActivity], theme: ShareCardTheme, defaultLine: String) {
        self.year = year; self.month = month; self.name = name
        self.nights = nights; self.hours = hours; self.activities = activities
        self.theme = theme; self.defaultLine = defaultLine
        _line = State(initialValue: defaultLine)
    }

    var body: some View {
        ShareCardScaffold(
            title: "Share your month",
            formats: [.story, .square],
            ink: theme.ink,
            controls: {
                TextField("a month of looking up", text: $line)
                    .font(.system(size: 16, design: .serif))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .onChange(of: line) { _, new in
                        if new.contains("\n") { line = new.replacingOccurrences(of: "\n", with: "") }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            },
            card: { format in
                MonthShareCardView(year: year, month: month, name: name, line: line,
                                   nights: nights, hours: hours, activities: activities,
                                   theme: theme, format: format)
            }
        )
    }
}
