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

/// A cover that reads as a separate layer floating above the page.
///
/// Deliberately does not rotate anything. `rotation3DEffect` is a flat affine
/// approximation of perspective — SwiftUI has no real camera or lens — and at
/// any angle large enough to actually notice, that approximation shows: the
/// cover foreshortens unevenly and can pick up an in-plane twist from
/// composing two rotations. Real depth cues in iOS (the Lock Screen
/// wallpaper, Wallet passes) mostly avoid rotating geometry at all; they
/// shift flat layers against each other. Copying that instead: the cover and
/// its shadow are two independent layers that translate a few points apart,
/// so the cover appears to hover over the page. Nothing ever changes shape,
/// so there's no tilt at which this can look warped.
private struct TiltedCover: View {

    let book: HomeBook
    let roll: Double
    let pitch: Double

    @Environment(\.appTheme) private var theme

    /// Points the cover itself drifts per degree of tilt. Kept small — this
    /// only needs to read as a layer separate from the page, not as the cover
    /// sliding around inside its grid cell.
    private let coverTranslationPerDegree: CGFloat = 0.16

    /// Points the shadow drifts, in the *opposite* direction from the cover,
    /// per degree of tilt. The shadow moving more than the cover — as though
    /// cast by a fixed light source while the card above it tilts — is the
    /// entire depth cue.
    private let shadowTranslationPerDegree: CGFloat = 0.34

    /// Where the shadow sits at rest (device flat), before any parallax offset.
    private let restingShadowOffset = CGSize(width: 0, height: 7)

    private var coverOffset: CGSize {
        CGSize(width: roll * coverTranslationPerDegree, height: -pitch * coverTranslationPerDegree)
    }

    private var shadowOffset: CGSize {
        CGSize(
            width: restingShadowOffset.width - roll * shadowTranslationPerDegree,
            height: restingShadowOffset.height + pitch * shadowTranslationPerDegree
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = width * 1.4
                let corner = RoundedRectangle(cornerRadius: 8, style: .continuous)

                // Two independent layers, not one view with a .shadow() —
                // .shadow() bakes the shadow into the same rendered output as
                // its view, so a single .offset() would move both together
                // and there would be no relative motion to read as depth.
                ZStack {
                    corner
                        .fill(theme.colors.spineShadow.opacity(0.35))
                        .frame(width: width, height: height)
                        .blur(radius: 10)
                        .offset(shadowOffset)

                    BookCoverView(book: book, width: width, height: height)
                        .clipShape(corner)
                        .offset(coverOffset)
                    // No .animation here — the provider already low-passes the
                    // signal. Animating on top would add lag and make the
                    // cover feel like it's chasing the phone.
                }
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
