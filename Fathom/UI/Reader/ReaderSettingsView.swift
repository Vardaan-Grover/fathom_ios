import SwiftUI

// MARK: - Main View

/// Reader settings, presented as a compact sheet that adopts the currently
/// selected book theme. It sits low enough that the page stays visible above
/// it, so every change previews live on the real text.
struct ReaderSettingsView: View {
    @Binding var settings: ReaderSettings

    @State private var tab: Tab = .theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Height of the resting detent. Every pane is sized to fit inside it, so
    /// the sheet never scrolls at rest and never jumps when panes change.
    private static let compactHeight: CGFloat = 392

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

            SegmentedTabs(selection: $tab, ink: ink)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)

            panes

            Spacer(minLength: 0)

            resetButton
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(surface.ignoresSafeArea())
        .tint(ink)
        // Render system controls (sliders, toggles) for the theme surface they
        // sit on, not for the app's own light/dark mode.
        .environment(\.colorScheme, settings.colorTheme.isDark ? .dark : .light)
        .presentationDetents([.height(Self.compactHeight), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(surface)
        .presentationCornerRadius(28)
        // Keep the page behind tappable/scrollable at the resting detent.
        .presentationBackgroundInteraction(.enabled(upThrough: .height(Self.compactHeight)))
    }

    // MARK: Theme-derived palette

    private var ink: Color { settings.colorTheme.foregroundColor }
    private var surface: Color { settings.colorTheme.backgroundColor }

    // MARK: Chrome

    private var grabber: some View {
        Capsule()
            .fill(ink.opacity(0.22))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 14)
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

    private var themePane: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
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
        VStack(alignment: .leading, spacing: 20) {
            fontSizeCard

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Typeface").padding(.horizontal, 20)
                fontScroll
            }

            optionsCard.padding(.horizontal, 20)
        }
        .transition(paneTransition)
    }

    private var fontSizeCard: some View {
        HStack(spacing: 14) {
            Text("A")
                .font(.system(size: 14))
                .foregroundStyle(ink.opacity(0.6))
            Slider(value: $settings.fontSize, in: 0.5...2.5, step: 0.1)
                .accessibilityLabel("Font size")
                .accessibilityValue("\(Int(settings.fontSize * 100)) percent")
            Text("A")
                .font(.system(size: 24))
                .foregroundStyle(ink.opacity(0.6))
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
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
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var optionsCard: some View {
        VStack(spacing: 0) {
            toggleRow("Justify Text", icon: "text.justify.leading", isOn: $settings.justifyText)
            rowDivider
            toggleRow("Bold Text", icon: "bold", isOn: $settings.boldText)
        }
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Layout pane

    private var layoutPane: some View {
        VStack(alignment: .leading, spacing: 20) {
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

    @ViewBuilder
    private var resetButton: some View {
        if settings != ReaderSettings() {
            Button {
                withAnimation(.snappy(duration: 0.3)) { settings = ReaderSettings() }
            } label: {
                Text("Reset to Defaults")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            .transition(.opacity)
        }
    }

    // MARK: Shared pieces

    private var fill: Color { ink.opacity(0.055) }

    private var paneTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(ink.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 50)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .kerning(0.9)
            .foregroundStyle(ink.opacity(0.45))
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
        .frame(height: 52)
    }
}

// MARK: - Segmented Tabs

private struct SegmentedTabs: View {
    @Binding var selection: ReaderSettingsView.Tab
    let ink: Color
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ReaderSettingsView.Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == tab ? ink : ink.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(ink.opacity(0.11))
                                    .matchedGeometryEffect(id: "segment", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(ink.opacity(0.05)))
        .animation(.snappy(duration: 0.3), value: selection)
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
            VStack(spacing: 8) {
                Text("Aa")
                    .font(font.swiftUIFont(size: 27))
                    .foregroundStyle(theme.foregroundColor)
                Text(theme.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foregroundColor.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Keeps near-white themes from dissolving into a near-white sheet.
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.foregroundColor.opacity(0.10), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ink, lineWidth: isSelected ? 2 : 0)
                    .padding(-3)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
                    .font(font.swiftUIFont(size: 23))
                    .foregroundStyle(ink)
                Text(font.cardLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink.opacity(0.5))
            }
            .frame(width: 76, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ink.opacity(isSelected ? 0.10 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ink.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 9) {
                PageModeThumbnail(mode: mode, ink: ink)
                    .frame(width: 42, height: 52)
                Text(mode.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.opacity(isSelected ? 0.9 : 0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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
        .buttonStyle(.plain)
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
                page(lines: 5)
                    .offset(x: 5)
                    .opacity(0.35)
                page(lines: 5)
                    .offset(x: -3)
            }
        case .curl:
            page(lines: 5)
                .overlay(alignment: .bottomTrailing) {
                    // The lifted corner.
                    Path { path in
                        path.move(to: CGPoint(x: 15, y: 15))
                        path.addLine(to: CGPoint(x: 15, y: 0))
                        path.addQuadCurve(
                            to: CGPoint(x: 0, y: 15),
                            control: CGPoint(x: 9, y: 9)
                        )
                        path.closeSubpath()
                    }
                    .fill(ink.opacity(0.32))
                    .frame(width: 15, height: 15)
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
                    .frame(maxWidth: index == lines - 1 ? 22 : .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ink.opacity(0.07))
        )
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
                .accessibilityLabel(label)
            Text(format(value))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(ink.opacity(0.5))
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
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
