import SwiftUI

// MARK: - ProfileHeaderCard
//
// Hero card at the top of the Settings screen. Big tappable avatar +
// display name + email. Tap avatar → emoji picker; tap name → name editor.

struct ProfileHeaderCard: View {
    let profile: UserProfile
    let email: String?
    var onTapAvatar: () -> Void
    var onTapName: () -> Void

    private var initials: String {
        UserProfile.initials(displayName: profile.displayName, email: email)
    }

    @State private var avatarPressed = false

    var body: some View {
        VStack(spacing: 18) {
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                onTapAvatar()
            }) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        emoji: profile.avatarEmoji,
                        initials: initials,
                        colorHex: profile.avatarColorHex,
                        diameter: 104
                    )

                    pencilBadge
                        .offset(x: 2, y: 2)
                }
                .scaleEffect(avatarPressed ? 0.96 : 1.0)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in avatarPressed = true }
                    .onEnded { _ in avatarPressed = false }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: avatarPressed)

            VStack(spacing: 4) {
                Button(action: onTapName) {
                    HStack(spacing: 6) {
                        Text(profile.displayName?.isEmpty == false
                             ? profile.displayName!
                             : "Add your name")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                profile.displayName?.isEmpty == false
                                ? AnyShapeStyle(.primary)
                                : AnyShapeStyle(.secondary)
                            )
                            .lineLimit(1)

                        if profile.displayName?.isEmpty != false {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)

                if let email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    private var pencilBadge: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}
