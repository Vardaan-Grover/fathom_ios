import SwiftUI
import UIKit

/// The two export shapes for a share card.
enum ShareCardFormat: String, CaseIterable, Identifiable {
    case story   // 9:16 — stories
    case square  // 1:1 — feed posts

    var id: String { rawValue }
    var label: String { self == .story ? "Story" : "Square" }

    /// Logical layout size; rendered at `renderScale` for crisp export pixels.
    var renderSize: CGSize {
        self == .story ? CGSize(width: 540, height: 960) : CGSize(width: 540, height: 540)
    }
    var renderScale: CGFloat { 3 }          // → 1620×2880 / 1620×1620
    var aspectRatio: CGFloat { renderSize.width / renderSize.height }
}

/// Concrete (already resolved for the current light/dark theme) colors a card
/// paints with — `ImageRenderer` doesn't carry `@Environment`, so we bake them.
struct ShareCardTheme {
    let background: Color
    let ink: Color
    let primary: Color
    let secondary: Color

    /// Resolve the app theme's dynamic colors to concrete values for a scheme.
    static func resolved(background: Color, ink: Color, primary: Color, secondary: Color,
                         scheme: ColorScheme) -> ShareCardTheme {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        func fix(_ c: Color) -> Color {
            Color(UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
        }
        return ShareCardTheme(background: fix(background), ink: ink,
                              primary: fix(primary), secondary: fix(secondary))
    }
}

/// Headline numbers for the year card.
struct ShareStats {
    let nightsRead: Int
    let totalSeconds: TimeInterval
    let booksFinished: Int

    var hoursText: String {
        let hours = totalSeconds / 3600
        if hours >= 1 { return String(Int(hours.rounded())) }
        return "<1"
    }

    /// Compute from the loaded activity + books for a given year.
    static func forYear(_ year: Int,
                        activities: [String: DailyActivity],
                        books: [UUID: Book]) -> ShareStats {
        let todayStart = Calendar.current.startOfDay(for: Date())
        var nights = 0
        var seconds: TimeInterval = 0
        for (_, activity) in activities where activity.duration > 0 {
            seconds += activity.duration
            if activity.date < todayStart { nights += 1 }   // settled nights only
        }
        let finished = books.values.filter {
            guard let d = $0.finishedAt else { return false }
            return Calendar.current.component(.year, from: d) == year
        }.count
        return ShareStats(nightsRead: nights, totalSeconds: seconds, booksFinished: finished)
    }
}
