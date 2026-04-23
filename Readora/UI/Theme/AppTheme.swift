import SwiftUI

// MARK: - AppTheme

/// The single source of truth for all design tokens in Readora.
///
/// Usage in any SwiftUI view:
/// ```swift
/// @Environment(\.appTheme) var theme
///
/// Text("Hello")
///     .font(theme.typography.headline)
///     .foregroundColor(theme.colors.primary)
/// ```
struct AppTheme {

    // MARK: Nested token groups

    let colors: Colors
    let typography: Typography
    let layout: Layout

    // MARK: Default

    /// The canonical Readora theme. Extend this if you need palettes (e.g. high-contrast).
    static let `default` = AppTheme(
        colors: .default,
        typography: .default,
        layout: .default
    )
}

// MARK: - AppTheme.Colors

extension AppTheme {

    /// Semantic color roles. All entries are adaptive — they resolve to the
    /// correct value for the current ColorScheme (light / dark) automatically.
    struct Colors {

        // ── Backgrounds ──────────────────────────────────────────────────────

        /// Primary canvas: warm parchment in light, warm near-black in dark.
        /// Backed by the `ReadoraBackground` Asset Catalog entry.
        let background: Color

        /// Elevated surface (cards, shelves, sheets).
        /// Backed by the `ReadoraSurface` Asset Catalog entry.
        let surface: Color

        // ── Content ───────────────────────────────────────────────────────────

        /// Primary body text and icons.
        let primary: Color

        /// Secondary / caption text, labels, and chevrons.
        let secondary: Color

        /// Dividers and subtle rule lines.
        let separator: Color

        // ── Brand / Accent ────────────────────────────────────────────────────

        /// Brand accent used for the bookshelf tint and interactive highlights.
        let shelfAccent: Color

        // ── Static (decorative) ───────────────────────────────────────────────

        /// Overlays a subtle shadow on book spine edges; always a semi-transparent black.
        let spineShadow: Color

        // MARK: Default

        static let `default` = Colors(
            background:  Color("ReadoraBackground"),
            surface:     Color("ReadoraSurface"),
            primary:     Color(.label),
            secondary:   Color(.secondaryLabel),
            separator:   Color(.separator),
            shelfAccent: Color(hex: "4A7DB5"),   // warm steel-blue, visible on both modes
            spineShadow: Color.black.opacity(0.28)
        )
    }
}

// MARK: - AppTheme.Typography

extension AppTheme {

    /// A curated type scale for Readora. Uses Dynamic Type compatible `Font` values
    /// so the system respects the user's Accessibility text-size preferences.
    struct Typography {

        // ── Display ───────────────────────────────────────────────────────────

        /// Large serif display font — used for the "BOOKS" hero heading.
        let displaySerif: Font

        // ── Hierarchy ─────────────────────────────────────────────────────────

        /// Section titles and view titles (bold, 20 pt).
        let title: Font

        /// Sub-section labels and sheet headings (semibold, 17 pt).
        let headline: Font

        /// Standard body copy (regular, 15 pt).
        let body: Font

        /// Secondary labels, metadata, tab labels (medium, 13 pt).
        let subheadline: Font

        /// Smallest labels — book counts, captions (regular, 11 pt).
        let caption: Font

        // ── Specialised ───────────────────────────────────────────────────────

        /// Book title overlay on a cover tile (bold, 12 pt).
        let coverTitle: Font

        /// Author name overlay on a cover tile (regular, 9 pt).
        let coverAuthor: Font

        // MARK: Default

        static let `default` = Typography(
            displaySerif:  .system(size: 72, weight: .regular, design: .serif),
            title:         .system(size: 20, weight: .bold),
            headline:      .system(size: 17, weight: .semibold),
            body:          .system(size: 15, weight: .regular),
            subheadline:   .system(size: 13, weight: .medium),
            caption:       .system(size: 11, weight: .regular),
            coverTitle:    .system(size: 12, weight: .bold),
            coverAuthor:   .system(size:  9, weight: .regular)
        )
    }
}

// MARK: - AppTheme.Layout

extension AppTheme {

    /// Consistent spacing and corner-radius constants.
    /// Centralising them here means a single edit reshapes the entire UI.
    struct Layout {

        // ── Corner Radii ──────────────────────────────────────────────────────

        /// 4 pt — tight elements like book cover tiles.
        let cornerRadiusSmall: CGFloat

        /// 8 pt — buttons, tags, shelf band.
        let cornerRadiusMedium: CGFloat

        /// 16 pt — cards, sheets.
        let cornerRadiusLarge: CGFloat

        // ── Spacing ───────────────────────────────────────────────────────────

        /// Standard left/right screen margin (20 pt).
        let horizontalPadding: CGFloat

        /// Vertical gap between major page sections (24 pt).
        let sectionSpacing: CGFloat

        // MARK: Default

        static let `default` = Layout(
            cornerRadiusSmall:  4,
            cornerRadiusMedium: 8,
            cornerRadiusLarge:  16,
            horizontalPadding:  20,
            sectionSpacing:     24
        )
    }
}
