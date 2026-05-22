import SwiftUI

// Curated palette of soft, modern avatar background colors.
// Hex values match the iOS system color aesthetic (slightly desaturated).
enum AvatarColors {
    static let palette: [String] = [
        "5B7CB0", // Indigo Blue
        "4A9D8E", // Teal
        "E07856", // Coral
        "C97BB4", // Lavender Pink
        "D9A441", // Amber
        "7A8F5F", // Sage
        "8B6F47", // Mocha
        "6E64B3", // Periwinkle
        "C25450", // Brick
        "47668A", // Slate
        "B36F8C", // Mauve
        "5C8C6E", // Forest
    ]

    /// Choose a deterministic palette color from a string seed (e.g. an email).
    static func deterministic(for seed: String) -> String {
        guard !seed.isEmpty else { return palette[0] }
        let sum = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

extension UserProfile {
    var avatarColor: Color { Color(hex: avatarColorHex) }

    /// Two-character initials derived from `displayName` (preferred) or `email`.
    static func initials(displayName: String?, email: String?) -> String {
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            let parts = name.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2,
               let a = parts.first?.first,
               let b = parts.dropFirst().first?.first {
                return "\(a)\(b)".uppercased()
            }
            if let first = name.first {
                return String(first).uppercased()
            }
        }
        if let email, let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }
}
