import SwiftUI

// MARK: - Main View

struct ReaderSettingsView: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sticky — stays visible regardless of scroll position
                ReaderPreviewCard(settings: settings)

                Divider()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("Theme")
                        themeGrid
                            .padding(.horizontal, 20)

                        sectionHeader("Font")
                        fontScroll

                        sectionHeader("Typography")
                        typographyCard
                            .padding(.horizontal, 20)

                        sectionHeader("Layout & Text")
                        layoutCard
                            .padding(.horizontal, 20)

                        resetButton
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 44)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.fraction(0.72), .large])
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
    }

    // MARK: - Theme grid

    private var themeGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
            spacing: 10
        ) {
            ForEach(ReaderColorTheme.allCases, id: \.self) { theme in
                ThemeCard(
                    theme: theme,
                    font: settings.font,
                    isSelected: settings.colorTheme == theme
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.colorTheme = theme
                    }
                }
            }
        }
    }

    // MARK: - Font scroll

    private var fontScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ReaderFont.allCases, id: \.self) { font in
                    FontCard(font: font, isSelected: settings.font == font) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            settings.font = font
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Typography card

    private var typographyCard: some View {
        VStack(spacing: 0) {
            SliderRow(
                icon: "textformat.size",
                label: "Text Size",
                value: $settings.fontSize,
                range: 0.5...2.5,
                step: 0.1,
                format: { String(format: "%.1f×", $0) }
            )
            Divider().padding(.leading, 54)
            SliderRow(
                icon: "line.3.horizontal",
                label: "Line Height",
                value: $settings.lineHeight,
                range: 1.0...2.0,
                step: 0.1,
                format: { String(format: "%.2f", $0) }
            )
            Divider().padding(.leading, 54)
            SliderRow(
                icon: "arrow.left.and.right",
                label: "Margin",
                value: $settings.margin,
                range: 0.5...2.5,
                step: 0.1,
                format: { String(format: "%.1f×", $0) }
            )
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Layout & text card

    private var layoutCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "book.pages")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                    .frame(width: 28)
                Text("Layout")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $settings.layout) {
                    Text("Pages").tag(ReadingLayout.paginated)
                    Text("Scroll").tag(ReadingLayout.scrolling)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().padding(.leading, 54)

            Toggle(isOn: $settings.justifyText) {
                Label("Justify Text", systemImage: "text.justify.leading")
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().padding(.leading, 54)

            Toggle(isOn: $settings.boldText) {
                Label("Bold Text", systemImage: "bold")
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                settings = ReaderSettings()
            }
        } label: {
            Text("Reset to Defaults")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview Card

private struct ReaderPreviewCard: View {
    let settings: ReaderSettings

    private let sampleText = "'But is it possible, is it really possible, that we shall never see each other again? Is it possible it will end like this?' 'There, you see,' the girl said, laughing, 'at first you wanted just two words, and now...'"

    // Clamp preview sizes so the card looks reasonable at any fontSize setting
    private var aaSize: CGFloat   { min(42.0 * settings.fontSize, 58.0) }
    private var bodySize: CGFloat { min(max(14.0 * settings.fontSize, 11.0), 20.0) }
    private var extraLineSpacing: CGFloat { bodySize * max(0, settings.lineHeight - 1.0) * 0.5 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background fills the full card — not masked
            settings.colorTheme.backgroundColor

            // Text content — masked so it fades into the background at the bottom
            VStack(alignment: .leading, spacing: 12) {
                Text("Aa")
                    .font(settings.font.swiftUIFont(size: aaSize))
                    .fontWeight(settings.boldText ? .bold : .regular)
                    .foregroundStyle(settings.colorTheme.foregroundColor)

                Text(sampleText)
                    .font(settings.font.swiftUIFont(size: bodySize))
                    .fontWeight(settings.boldText ? .bold : .regular)
                    .foregroundStyle(settings.colorTheme.foregroundColor)
                    .lineSpacing(extraLineSpacing)
                    .multilineTextAlignment(settings.justifyText ? .leading : .leading)
                    .lineLimit(8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask(
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 48)
                }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
        .clipped()
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: ReaderColorTheme
    let font: ReaderFont
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.backgroundColor)

                VStack(spacing: 3) {
                    Text("Aa")
                        .font(font.swiftUIFont(size: 24))
                        .foregroundStyle(theme.foregroundColor)
                    Text(theme.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.foregroundColor.opacity(0.65))
                }

                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            }
            .frame(height: 78)
            .scaleEffect(isSelected ? 1.0 : 0.97)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Font Card

private struct FontCard: View {
    let font: ReaderFont
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))

                VStack(spacing: 4) {
                    Text("Aa")
                        .font(font.swiftUIFont(size: 24))
                        .foregroundStyle(.primary)
                    Text(font.cardLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
            .frame(width: 74, height: 74)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slider Row

private struct SliderRow: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .frame(width: 28)
            Text(label)
                .font(.subheadline)
            Slider(value: $value, in: range, step: step)
            Text(format(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - ReaderFont SwiftUI helpers

private extension ReaderFont {
    func swiftUIFont(size: CGFloat) -> Font {
        switch self {
        case .original:      .system(size: size)
        case .newYork:       .system(size: size, design: .serif)
        case .georgia:       .custom("Georgia", size: size)
        case .palatino:      .custom("Palatino", size: size)
        case .iowanOldStyle: .custom("Iowan Old Style", size: size)
        case .charter:       .custom("Charter", size: size)
        case .sfProText:     .system(size: size)
        case .avenir:        .custom("Avenir", size: size)
        }
    }

    var cardLabel: String {
        switch self {
        case .original:      "Original"
        case .newYork:       "New York"
        case .georgia:       "Georgia"
        case .palatino:      "Palatino"
        case .iowanOldStyle: "Iowan"
        case .charter:       "Charter"
        case .sfProText:     "SF Pro"
        case .avenir:        "Avenir"
        }
    }
}
