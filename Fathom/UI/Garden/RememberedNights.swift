import Foundation

/// Persistent set of "remembered" nights — days a user marks as reading they did
/// *before* Fathom tracked it. Purely visual (ghosted doodles); never counted as
/// tracked history. Stored as `yyyy-MM-dd` keys in UserDefaults.
enum RememberedNights {
    private static let key = "memoryGarden.rememberedNights"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    /// A stable, varied pseudo-duration for a remembered night, so it earns a
    /// doodle that mixes tiers across the garden without storing per-night detail.
    static func duration(forDayOfYear day: Int) -> TimeInterval {
        switch abs(day &* 2_654_435_761) % 3 {
        case 0:  return 10 * 60     // a glimpse
        case 1:  return 30 * 60     // settled in
        default: return 70 * 60     // a grand night
        }
    }
}
