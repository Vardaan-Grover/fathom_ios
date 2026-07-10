import SwiftUI

/// The marquee share card: a framed page of your whole reading year. No
/// `@Environment` (rendered via `ImageRenderer`) — all colors come from `theme`.
/// Fills whatever size it's given (the caller frames it to the chosen format).
struct YearShareCardView: View {
    let year: Int
    let name: String
    let line: String
    let stats: ShareStats
    let durations: [TimeInterval]
    var columns: Int = 14
    let theme: ShareCardTheme
    let format: ShareCardFormat

    private var story: Bool { format == .story }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, story ? 56 : 34)
                .padding(.horizontal, 34)

            GardenGridStatic(durations: durations, ink: theme.ink, columns: columns)
                .padding(.horizontal, 30)
                .padding(.vertical, story ? 26 : 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            statsRow
                .padding(.horizontal, 40)

            if !line.isEmpty {
                Text(line)
                    .font(.custom("Reenie Beanie", size: 32))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 34)
            }

            Text("made with Fathom ✦")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .tracking(0.5)
                .foregroundStyle(theme.secondary)
                .padding(.top, 16)
                .padding(.bottom, story ? 50 : 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    private var header: some View {
        VStack(spacing: 2) {
            if !name.isEmpty {
                Text("\(name.uppercased())’S READING YEAR")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(theme.secondary)
            } else {
                Text("A READING YEAR")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .tracking(2)
                    .foregroundStyle(theme.secondary)
            }
            Text(String(year))
                .font(.system(size: story ? 62 : 50, weight: .bold, design: .serif))
                .foregroundStyle(theme.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("\(stats.nightsRead)", stats.nightsRead == 1 ? "night read" : "nights read")
            rule
            stat(stats.hoursText, "hours")
            rule
            stat("\(stats.booksFinished)", stats.booksFinished == 1 ? "book" : "books")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(theme.ink)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .tracking(1)
                .foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var rule: some View {
        Rectangle()
            .fill(theme.secondary.opacity(0.25))
            .frame(width: 1, height: 30)
    }
}
