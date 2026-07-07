import SwiftUI

/// What the observatory hands the garden to run a reveal.
struct RevealRequest: Equatable {
    let doodleName: String
    let date: Date
    let tierTitle: String
}

/// The reveal ceremony, hosted *over the real garden*. A frosted-glass card hides
/// the doodle behind blur (curiosity); a tap clears the frost to reveal it; then
/// "Add to your garden" flies the doodle (a shared `matchedGeometryEffect` hero)
/// into its real day cell on the month grid behind.
struct RevealOverlay: View {
    let request: RevealRequest
    let ink: Color
    let heroNamespace: Namespace.ID
    let isFrosted: Bool
    /// True during the flight — the hero is handed to the grid cell, the glass clears.
    let isLeaving: Bool
    var onUnveil: () -> Void
    var onLand: () -> Void
    var onSkip: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // The garden frosts over behind the card, then clears as we land.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(isLeaving ? 0 : 1)
            Color.black.opacity(isLeaving ? 0 : 0.12).ignoresSafeArea()

            // Skip (so you're never trapped before tapping through).
            VStack {
                HStack {
                    Spacer()
                    Button(action: onSkip) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 34, height: 34)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isLeaving ? 0 : 1)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            if !isLeaving {
                card
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.5), value: isLeaving)
    }

    private var card: some View {
        VStack(spacing: 12) {
            hero
                .padding(.bottom, 2)

            if isFrosted {
                Text("last night, you spotted…")
                    .font(.reenie(38))
                    .foregroundColor(.primary.opacity(0.8))
                Text("tap to reveal")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            } else {
                Text("you spotted")
                    .font(.system(size: 16, weight: .regular, design: .serif)).italic()
                    .foregroundColor(.secondary)
                Text(DoodleCatalog.phrase(for: request.doodleName))
                    .font(.reenie(52))
                    .foregroundColor(ink)
                    .multilineTextAlignment(.center)
                Text(metaText)
                    .font(.system(size: 10.5, weight: .semibold, design: .serif))
                    .tracking(1.4)
                    .foregroundColor(.secondary)

                Button(action: onLand) {
                    Text("Add to your garden")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(ink))
                        .shadow(color: ink.opacity(0.4), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .padding(28)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.5), lineWidth: 1)
        )
        .shadow(color: ink.opacity(0.2), radius: 30, y: 14)
        .contentShape(Rectangle())
        .onTapGesture { if isFrosted { onUnveil() } }
    }

    private var hero: some View {
        ZStack {
            // A glow that's brighter while frosted (the "something's there" pull).
            RadialGradient(colors: [ink.opacity(isFrosted ? 0.5 : 0.32), .clear],
                           center: .center, startRadius: 2, endRadius: 100)
                .frame(width: 200, height: 160)
                .blur(radius: 16)

            Image(request.doodleName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(ink)
                .frame(height: 116)
                .shadow(color: ink.opacity(0.4), radius: 10)
                .matchedGeometryEffect(id: "revealHero", in: heroNamespace)
                .blur(radius: isFrosted ? 13 : 0)
        }
        .frame(height: 150)
    }

    private var metaText: String {
        let when: String
        if Calendar.current.isDateInYesterday(request.date) {
            when = "last night"
        } else {
            let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
            when = f.string(from: request.date)
        }
        return "\(request.tierTitle) · \(when)".uppercased()
    }
}
