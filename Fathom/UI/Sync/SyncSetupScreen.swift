import SwiftUI

/// The first thing a reader sees on a new device, while their library arrives
/// from iCloud.
///
/// It exists because the alternative is worse, not because waiting is nice: a
/// first sync moves a few hundred records, and without this the library screen
/// is mounted the whole time — empty, then half-populated, then reordering
/// itself as shelves land. A surface that says plainly "this is happening once"
/// is calmer than one that looks broken while it works.
///
/// Visually it is the same hand it draws everywhere else: one template doodle
/// lit by a blur of itself, a serif line, and nothing that spins. The doodle is
/// someone shelving books, which is what the app is doing while you wait.
struct SyncSetupScreen: View {

    @ObservedObject var activity: SyncActivity

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false
    @State private var breathe = false

    private var ink: Color { theme.colors.primary }

    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                shelving
                    .padding(.bottom, 30)

                Text("Bringing your library across")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)

                Text("Your books, shelves and notes are arriving from iCloud. This only happens once on a new device.")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)

                arrivals
                    .padding(.top, 26)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .opacity(hasAppeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { hasAppeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bringing your library across from iCloud")
        .accessibilityValue(activity.received > 0 ? "\(activity.received) items so far" : "")
    }

    // MARK: - Doodle

    private var shelving: some View {
        ZStack {
            // Same ink-bleed treatment as the empty library: the halo is the
            // artwork blurred against itself, so it traces the drawing's own
            // strokes instead of sitting behind it as a disc.
            //
            // Lighter on dark than the empty-library shelf uses. That drawing
            // is fine parallel lines; this one carries large filled areas, and
            // the shelf's opacities turn them into a lamp rather than a halo.
            shelvingArt
                .blur(radius: 24)
                .opacity(colorScheme == .dark ? 0.32 : 0.16)
                .scaleEffect(1.03)

            shelvingArt
                .blur(radius: 7)
                .opacity(colorScheme == .dark ? 0.18 : 0.1)

            shelvingArt
        }
        .offset(y: breathe ? -5 : 5)
        .scaleEffect(breathe ? 1.015 : 0.985)
        .padding(40)
        .drawingGroup()
        .padding(-40)
    }

    private var shelvingArt: some View {
        Image("ArrangingBooks")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(ink)
            // Taller than the shelf doodle is drawn at, because this artwork
            // sits inside a lot of transparent canvas — the figure ends up
            // noticeably smaller than the nominal height suggests.
            .frame(height: 240)
    }

    // MARK: - Progress

    /// A count, not a bar. CloudKit does not say how many records are coming,
    /// so a percentage would be a number we made up — and a bar that stalls at
    /// 90% is exactly the kind of thing this screen exists to avoid.
    @ViewBuilder
    private var arrivals: some View {
        VStack(spacing: 14) {
            travellingRule

            Text(activity.received > 0
                 ? "\(activity.received) items so far"
                 : "Looking for your library")
                .font(theme.typography.caption)
                .monospacedDigit()
                .foregroundStyle(theme.colors.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: activity.received)
        }
    }

    /// An indeterminate rule with a slow highlight passing along it. Reads as
    /// "still working" without claiming to know how far along it is.
    private var travellingRule: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule()
                .fill(ink.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [ink.opacity(0), ink.opacity(0.45), ink.opacity(0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.4)
                        .offset(x: breathe ? width * 0.6 : -width * 0.4)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 1.6).repeatForever(autoreverses: false),
                            value: breathe
                        )
                }
                .clipShape(Capsule())
        }
        .frame(width: 140, height: 3)
    }
}

// MARK: - Preview

#Preview {
    SyncSetupScreen(activity: .shared)
}
