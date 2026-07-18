import SwiftUI

// MARK: - Main View

/// Reader settings, presented as a compact sheet that adopts the currently
/// selected book theme. It sits low enough that the page stays visible above
/// it, so every change previews live on the real text.
///
/// Controls are the system's own (segmented `Picker`, `Toggle`, `Slider`), so
/// they carry iOS 26's Liquid Glass treatment, tinted to the theme's ink.
struct ReaderSettingsView: View {
    @Binding var settings: ReaderSettings

    @State private var tab: Tab = .theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sized to the tallest pane (Text) plus chrome and the reset row, so no
    /// pane scrolls at rest and the sheet never resizes between tabs.
    private static let sheetHeight: CGFloat = 392

    enum Tab: Int, CaseIterable, Identifiable {
        case theme, text, layout
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .theme: "Theme"
            case .text: "Text"
            case .layout: "Layout"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // Everything fits at rest; the scroll only engages for large
            // Dynamic Type.
            ScrollView {
                panes
            }
            .scrollBounceBehavior(.basedOnSize)

            resetButton
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(sheetSurface.ignoresSafeArea())
        .tint(ink)
        .environment(\.colorScheme, settings.colorTheme.isDark ? .dark : .light)
        // One detent: every pane already fits, so expanding only opened a void.
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(sheetSurface)
        // No presentationBackgroundInteraction: it makes the sheet non-modal,
        // which iOS 26 renders as a floating glass panel that blooms under
        // touch. The page only needs to be *visible* to preview live, not
        // tappable.
    }

    // MARK: Theme-derived palette

    private var ink: Color { settings.colorTheme.foregroundColor }
    private var surface: Color { settings.colorTheme.backgroundColor }
    private var fill: Color { ink.opacity(0.055) }
    private var hairline: Color { ink.opacity(0.08) }

    /// The theme's own paper, nudged 4% toward its ink. Without this the sheet
    /// is the exact color of the page behind it and its edge vanishes. Mixed
    /// into a single opaque Color rather than stacked as a translucent layer,
    /// so nothing shows through it.
    private var sheetSurface: Color {
        var base = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        var over = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        UIColor(surface).getRed(&base.r, green: &base.g, blue: &base.b, alpha: &base.a)
        UIColor(ink).getRed(&over.r, green: &over.g, blue: &over.b, alpha: &over.a)
        let t: CGFloat = 0.04
        return Color(
            red: base.r + (over.r - base.r) * t,
            green: base.g + (over.g - base.g) * t,
            blue: base.b + (over.b - base.b) * t
        )
    }

    // MARK: Chrome

    private var grabber: some View {
        Capsule()
            .fill(ink.opacity(0.22))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var panes: some View {
        ZStack(alignment: .top) {
            switch tab {
            case .theme: themePane
            case .text: textPane
            case .layout: layoutPane
            }
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.28), value: tab)
    }

    // MARK: Theme pane

    /// Two columns, three rows — fills the pane exactly, so the tab has no
    /// dead space despite holding the least content.
    private var themePane: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
            spacing: 12
        ) {
            ForEach(ReaderColorTheme.allCases, id: \.self) { theme in
                ThemeCard(
                    theme: theme,
                    font: settings.font,
                    isSelected: settings.colorTheme == theme,
                    ink: ink
                ) {
                    withAnimation(.snappy(duration: 0.3)) { settings.colorTheme = theme }
                }
            }
        }
        .padding(.horizontal, 20)
        .transition(paneTransition)
    }

    // MARK: Text pane

    private var textPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            fontSizeCard

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Typeface").padding(.horizontal, 20)
                fontScroll
            }

            optionsCard.padding(.horizontal, 20)
        }
        .transition(paneTransition)
    }

    /// Apple Books' two big targets, plus the numeric size between them.
    private var fontSizeCard: some View {
        HStack(spacing: 0) {
            sizeButton(glyph: 15, decrease: true)

            verticalHairline

            Text("\(Int((settings.fontSize * 100).rounded()))%")
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(ink.opacity(0.7))
                .frame(width: 62)
                .accessibilityHidden(true)

            verticalHairline

            sizeButton(glyph: 24, decrease: false)
        }
        .frame(height: 48)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func sizeButton(glyph: CGFloat, decrease: Bool) -> some View {
        let enabled = decrease ? settings.fontSize > 0.5 : settings.fontSize < 2.5
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                let steps = round(settings.fontSize * 10) + (decrease ? -1 : 1)
                settings.fontSize = min(2.5, max(0.5, steps / 10))
            }
        } label: {
            Text("A")
                .font(.system(size: glyph))
                .foregroundStyle(ink.opacity(enabled ? 1 : 0.25))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(InkPress())
        .disabled(!enabled)
        .accessibilityLabel(decrease ? "Decrease font size" : "Increase font size")
        .accessibilityValue("\(Int((settings.fontSize * 100).rounded())) percent")
    }

    private var fontScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ReaderFont.allCases, id: \.self) { font in
                    FontCard(font: font, isSelected: settings.font == font, ink: ink) {
                        withAnimation(.snappy(duration: 0.25)) { settings.font = font }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            toggleRow("Justify Text", icon: "text.justify.leading", isOn: $settings.justifyText)
            rowDivider
            toggleRow("Bold Text", icon: "bold", isOn: $settings.boldText)
        }
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toggleRow(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(ink.opacity(0.55))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(ink)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    // MARK: Layout pane

    private var layoutPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Page Turn")
                HStack(spacing: 12) {
                    ForEach(PageMode.allCases) { mode in
                        PageModeCard(mode: mode, isSelected: mode == currentPageMode, ink: ink) {
                            withAnimation(.snappy(duration: 0.3)) { apply(mode) }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Spacing")
                spacingCard
            }
        }
        .padding(.horizontal, 20)
        .transition(paneTransition)
    }

    private var spacingCard: some View {
        VStack(spacing: 0) {
            SliderRow(
                icon: "line.3.horizontal",
                label: "Line Height",
                value: $settings.lineHeight,
                range: 1.0...2.0,
                step: 0.1,
                ink: ink,
                format: { String(format: "%.1f", $0) }
            )
            rowDivider
            SliderRow(
                icon: "arrow.left.and.right",
                label: "Margins",
                value: $settings.margin,
                range: 0.5...2.5,
                step: 0.1,
                ink: ink,
                format: { String(format: "%.1f×", $0) }
            )
        }
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var currentPageMode: PageMode {
        if settings.layout == .scrolling { return .scroll }
        return settings.isCurlEnabled ? .curl : .slide
    }

    private func apply(_ mode: PageMode) {
        switch mode {
        case .slide:
            settings.layout = .paginated
            settings.pageTurnStyle = .slide
        case .curl:
            settings.layout = .paginated
            settings.pageTurnStyle = .curl
        case .scroll:
            settings.layout = .scrolling
            settings.pageTurnStyle = .slide
        }
    }

    // MARK: Reset

    private var isDefault: Bool { settings == ReaderSettings() }

    /// Only offered once there's something to undo, but its space is always
    /// reserved so appearing never shoves the panes around.
    private var resetButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { settings = ReaderSettings() }
        } label: {
            Text("Reset to Defaults")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(InkPress())
        .padding(.horizontal, 20)
        .opacity(isDefault ? 0 : 1)
        .disabled(isDefault)
        .accessibilityHidden(isDefault)
        .animation(.easeInOut(duration: 0.2), value: isDefault)
    }

    // MARK: Shared pieces

    private var paneTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    private var rowDivider: some View {
        Rectangle().fill(hairline).frame(height: 1).padding(.leading, 50)
    }

    private var verticalHairline: some View {
        Rectangle().fill(hairline).frame(width: 1).padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .kerning(0.9)
            .foregroundStyle(ink.opacity(0.45))
    }
}

// MARK: - Press feedback

/// Flat press feedback — the ink fades, nothing shines.
private struct InkPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: ReaderColorTheme
    let font: ReaderFont
    let isSelected: Bool
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("Aa")
                    .font(font.swiftUIFont(size: 28))
                    .foregroundStyle(theme.foregroundColor)
                Text(theme.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundColor.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Drawn inside the bounds: an outset ring gets clipped by the
            // enclosing ScrollView on the top row.
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? ink : theme.foregroundColor.opacity(0.12),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(InkPress())
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Font Card

private struct FontCard: View {
    let font: ReaderFont
    let isSelected: Bool
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text("Aa")
                    .font(font.swiftUIFont(size: 22))
                    .foregroundStyle(ink)
                Text(font.cardLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink.opacity(0.5))
            }
            .frame(width: 74, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ink.opacity(isSelected ? 0.10 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ink.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5)
            )
        }
        .buttonStyle(InkPress())
        .accessibilityLabel(font.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Page Mode

enum PageMode: Int, CaseIterable, Identifiable {
    case slide, curl, scroll
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .slide: "Slide"
        case .curl: "Curl"
        case .scroll: "Scroll"
        }
    }
}

private struct PageModeCard: View {
    let mode: PageMode
    let isSelected: Bool
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                PageModeThumbnail(mode: mode, ink: ink)
                    .frame(width: 40, height: 50)
                Text(mode.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.opacity(isSelected ? 0.9 : 0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ink.opacity(isSelected ? 0.10 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ink.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(InkPress())
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Miniature of a page behaving in each mode, so the choice reads without
/// having to try it.
private struct PageModeThumbnail: View {
    let mode: PageMode
    let ink: Color

    var body: some View {
        switch mode {
        case .slide:
            ZStack {
                page(lines: 5).offset(x: 5).opacity(0.35)
                page(lines: 5).offset(x: -3)
            }
        case .curl:
            page(lines: 5)
                .overlay(alignment: .bottomTrailing) {
                    // The lifted corner.
                    Path { path in
                        path.move(to: CGPoint(x: 14, y: 14))
                        path.addLine(to: CGPoint(x: 14, y: 0))
                        path.addQuadCurve(to: CGPoint(x: 0, y: 14), control: CGPoint(x: 8, y: 8))
                        path.closeSubpath()
                    }
                    .fill(ink.opacity(0.32))
                    .frame(width: 14, height: 14)
                }
        case .scroll:
            page(lines: 8)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private func page(lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<lines, id: \.self) { index in
                Capsule()
                    .fill(ink.opacity(0.4))
                    .frame(height: 2.5)
                    // Ragged last line, so it reads as prose.
                    .frame(maxWidth: index == lines - 1 ? 20 : .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ink.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ink.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Slider Row

private struct SliderRow: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let ink: Color
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(ink.opacity(0.55))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(ink)
                .frame(width: 84, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(format(value))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(ink.opacity(0.5))
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            default: break
            }
        }
    }
}

// MARK: - ReaderFont SwiftUI helpers

extension ReaderFont {
    fileprivate func swiftUIFont(size: CGFloat) -> Font {
        switch self {
        case .original: .system(size: size)
        case .newYork: .system(size: size, design: .serif)
        case .georgia: .custom("Georgia", size: size)
        case .palatino: .custom("Palatino", size: size)
        case .iowanOldStyle: .custom("Iowan Old Style", size: size)
        case .charter: .custom("Charter", size: size)
        case .sfProText: .system(size: size)
        case .avenir: .custom("Avenir", size: size)
        }
    }

    fileprivate var cardLabel: String {
        switch self {
        case .original: "Original"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .iowanOldStyle: "Iowan"
        case .charter: "Charter"
        case .sfProText: "SF Pro"
        case .avenir: "Avenir"
        }
    }
}
