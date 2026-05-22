import SwiftUI

// MARK: - AvatarView
//
// Renders a profile avatar. Shows the user's chosen emoji on a tinted
// circular background, or falls back to initials when no emoji is set.

struct AvatarView: View {
    let emoji: String?
    let initials: String
    let colorHex: String
    var diameter: CGFloat = 96

    private var bg: Color { Color(hex: colorHex) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [bg.opacity(0.85), bg],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: bg.opacity(0.35), radius: 12, x: 0, y: 6)

            if let emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: diameter * 0.58))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else {
                Text(initials)
                    .font(.system(size: diameter * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .kerning(-0.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }
}
