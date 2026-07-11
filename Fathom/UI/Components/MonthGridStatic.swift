import SwiftUI

/// A static S–M–T–W–T–F–S month calendar for the share card — the same layout as
/// the live month view, but plain (no animation / `@Environment`) so it
/// rasterizes cleanly through `ImageRenderer`. Cells are sized to fill the
/// available height, so a tall (story) card gets big legible doodles instead of
/// dead whitespace.
struct MonthGridStatic: View {
    let year: Int
    let month: Int
    let activities: [String: DailyActivity]
    let ink: Color
    let secondary: Color

    private let calendar = Calendar.current
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private static let key: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        GeometryReader { geo in
            let rows = max(1, Int(ceil(Double(cells.count) / 7.0)))
            let headerHeight: CGFloat = 22
            let rowSpacing: CGFloat = 6
            let gridHeight = geo.size.height - headerHeight - 16 - rowSpacing * CGFloat(rows - 1)
            let cellH = max(30, gridHeight / CGFloat(rows))

            VStack(spacing: 16) {
                HStack(spacing: 2) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .foregroundStyle(secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: headerHeight)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: rowSpacing) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                        cell(date, height: cellH)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ date: Date?, height: CGFloat) -> some View {
        if let date {
            let duration = activities[Self.key.string(from: date)]?.duration ?? 0
            let doodle = settledDoodle(for: date, duration: duration)
            let dayNum = calendar.component(.day, from: date)
            VStack(spacing: 2) {
                ZStack {
                    if let doodle {
                        Image(doodle)
                            .renderingMode(.template).resizable().scaledToFit()
                            .foregroundStyle(ink)
                            .frame(height: min(height * 0.58, 54))
                    } else {
                        Circle().fill(ink.opacity(0.16)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: height * 0.66)

                Text("\(dayNum)")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(doodle != nil ? ink.opacity(0.7) : secondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            Color.clear.frame(height: height)
        }
    }

    // MARK: Calendar math (matches MonthGardenView)

    private func settledDoodle(for date: Date, duration: TimeInterval) -> String? {
        guard date < calendar.startOfDay(for: Date()) else { return nil }
        let doy = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return DoodleCatalog.assetName(forDayOfYear: doy, duration: duration)
    }

    private var startOfMonth: Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }
    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
    }
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
}
