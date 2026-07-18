import SwiftUI

/// Two-column cover grid shown while search is open. With an empty query this
/// is the whole library; typing filters it down in place.
struct LibrarySearchResults: View {

    let books: [HomeBook]
    let isEmptyResult: Bool
    let query: String
    let onTap: (UUID) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var tilt = DeviceTiltProvider()

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    var body: some View {
        Group {
            if isEmptyResult {
                emptyState
            } else {
                grid
            }
        }
        .onAppear {
            // Reduce Motion means no gyro at all — don't even power the
            // sensors for an effect we're going to discard.
            if !reduceMotion { tilt.start() }
        }
        .onDisappear { tilt.stop() }
        .onChange(of: reduceMotion) { _, isReduced in
            isReduced ? tilt.stop() : tilt.start()
        }
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 26) {
                ForEach(books) { book in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onTap(book.id)
                    } label: {
                        TiltedCover(book: book, roll: tilt.roll, pitch: tilt.pitch)
                    }
                    .buttonStyle(.plain)
                    // Keyed by id so filtering reflows existing tiles rather
                    // than tearing them down and rebuilding.
                    .id(book.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.horizontal, theme.layout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 96)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: books)
        }
        // The keyboard follows the drag, but the search surface stays up —
        // losing focus is not intent to close, only Cancel is.
        .scrollDismissesKeyboard(.interactively)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.colors.secondary.opacity(0.5))
            Text("No books match \u{201C}\(query)\u{201D}")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.colors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .transition(.opacity)
    }
}

// MARK: - Tilted cover

/// A cover that leans with the device, as though sitting under glass.
private struct TiltedCover: View {

    let book: HomeBook
    let roll: Double
    let pitch: Double

    @Environment(\.appTheme) private var theme

    /// How much of the device's tilt the cover takes on.
    private let responsiveness: Double = 0.8

    /// Hard ceiling on the *combined* tilt. The provider clamps roll and pitch
    /// independently, but they compose — a diagonal lean reaches √(r² + p²),
    /// which is why clamping only the inputs let the covers reach ~28° and
    /// look like they were falling over.
    private let maxTiltDegrees: Double = 12

    /// Strength of the foreshortening. Kept modest: past ~0.5 the near edge
    /// balloons enough that the cover overruns its grid cell.
    private let perspective: Double = 0.45

    /// A single rotation about one axis, rather than chained Y-then-X ones.
    /// Composing two rotations introduces a Z component, which reads as the
    /// cover twisting in-plane — invisible at a few degrees, glaring past ten.
    private var tiltAngle: Double {
        min((roll * roll + pitch * pitch).squareRoot() * responsiveness, maxTiltDegrees)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let width = proxy.size.width
                BookCoverView(book: book, width: width, height: width * 1.4)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(
                        color: theme.colors.spineShadow.opacity(0.35),
                        // The shadow slides opposite the tilt, so the covers
                        // read as lifted off the page rather than painted on.
                        radius: 10, x: -roll * 0.3, y: 7 + pitch * 0.2
                    )
                    // Axis leans in whichever direction the device does, and
                    // z is always 0 — so the cover can never twist in-plane.
                    .rotation3DEffect(
                        .degrees(tiltAngle),
                        axis: (x: -pitch, y: roll, z: 0),
                        perspective: perspective
                    )
                    // No .animation here — the provider already low-passes the
                    // signal. Animating on top would add lag and make the
                    // covers feel like they're chasing the phone.
            }
            .aspectRatio(1 / 1.4, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primary)
                    .lineLimit(2)
                Text(book.author)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A tilted cover renders slightly outside its own layout bounds.
            // Keep the label above it so a near edge leaning down can never
            // occlude the title.
            .zIndex(1)
        }
    }
}
