import SwiftUI

/// Offers to catch this device up to wherever another one got to.
///
/// The case it answers: you read to 60% on one phone, then open the book on the
/// other. That second phone writes a position as soon as the book opens, so its
/// timestamp is newer and its position wins — leaving you at 10% with no way
/// back other than scrubbing. The high-water mark knows better, and this is
/// where it finally says so.
///
/// Deliberately not an alert. An alert would stop the reader from reading until
/// they answer a question they did not ask, and the honest default here is to
/// carry on where they are — so this sits at the foot of the page, leaves the
/// text alone, and is as easy to ignore as to take.
struct ReadingJumpPrompt: View {

    /// Progression another device reached, 0...1.
    let progression: Double
    let onJump: () -> Void
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false

    private var percentage: Int { Int((progression * 100).rounded()) }

    var body: some View {
        VStack(spacing: 12) {
            Text("You read to \(percentage)% on another device.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.colors.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Stay here")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.colors.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Button(action: onJump) {
                    Text("Jump there")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.colors.surface)
                // Warm, never grey — the shadow rule the rest of the app follows.
                .shadow(color: Color(red: 0.47, green: 0.27, blue: 0.07).opacity(0.28),
                        radius: 18, x: 0, y: 8)
        )
        .padding(.horizontal, 24)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .onAppear {
            guard !reduceMotion else { hasAppeared = true; return }
            withAnimation(.spring(duration: 0.42, bounce: 0.14)) { hasAppeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("You read to \(percentage) percent on another device")
    }
}

// MARK: - Preview

#Preview {
    ReadingJumpPrompt(progression: 0.6, onJump: {}, onDismiss: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(AppTheme.default.colors.background)
}
