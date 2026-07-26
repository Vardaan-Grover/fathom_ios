import SwiftUI
import UIKit

/// Shown on both library surfaces (HomeScreen and ClassicLibraryView) when the
/// user has no books yet — the very first thing a new reader sees.
///
/// The shelf is one of the hand-drawn doodles, rendered as a template so it
/// picks up the ink color of whichever surface is active (paper by day, sky by
/// night), and lit with the same soft radial glow the garden uses behind its
/// doodles. It breathes on a slow loop so the screen doesn't read as static
/// chrome — suppressed under Reduce Motion.
struct EmptyLibraryView: View {

    let onAddBook: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the entrance fade — separate from `breathe` so the appear
    /// animation isn't caught up in the repeating one.
    @State private var hasAppeared = false
    @State private var breathe = false

    private var ink: Color { theme.colors.primary }

    var body: some View {
        VStack(spacing: 0) {
            shelf
                .padding(.bottom, 28)

            Text("Your shelves are empty")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)

            Text("Add an EPUB and it will find its place here.")
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            addButton
                .padding(.top, 28)
        }
        .padding(.horizontal, 24)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { hasAppeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shelf

    private var shelf: some View {
        ZStack {
            // The glow is the artwork blurred against itself, not a gradient
            // behind it. A RadialGradient renders as a uniform disc with a
            // visible edge — a spotlight the shelf happens to sit in — which
            // the dark surface makes obvious. Blurring the line art instead
            // makes the halo trace the shelf's own strokes, the way ink bleeds
            // into paper: dense where lines converge, absent through the empty
            // bays. Two passes because one wide blur alone loses the drawing's
            // structure, and one tight blur alone doesn't carry far enough.
            shelfArt
                .blur(radius: 24)
                .opacity(colorScheme == .dark ? 0.5 : 0.16)
                .scaleEffect(1.03)

            shelfArt
                .blur(radius: 7)
                .opacity(colorScheme == .dark ? 0.34 : 0.1)

            shelfArt
        }
        // The doodle is line art on a transparent field, so the drift has to
        // stay small — a couple of points reads as a hover, more reads as a bug.
        .offset(y: breathe ? -5 : 5)
        .scaleEffect(breathe ? 1.015 : 0.985)
        // Room for the wide blur to spread before rasterizing, then reclaimed
        // so the glow doesn't push the copy below it down the screen.
        .padding(40)
        // Composite the stack once; the offset/scale then animate a static
        // texture instead of re-blurring the PNG every frame.
        .drawingGroup()
        .padding(-40)
    }

    private var shelfArt: some View {
        Image("EmptyShelf")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(ink)
            .frame(height: 210)
    }

    // MARK: - CTA

    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAddBook()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("Add your first book")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add your first book")
    }
}

// MARK: - Preview

#Preview {
    EmptyLibraryView(onAddBook: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.default.colors.background)
}
