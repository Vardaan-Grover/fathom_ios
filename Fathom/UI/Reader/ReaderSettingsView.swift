import SwiftUI

// MARK: - Main View

struct ReaderSettingsView: View {
    @Binding var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Reader Settings")
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        topRowControls
                            .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Font")
                            fontScroll
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Themes")
                            themeGrid
                                .padding(.horizontal, 20)
                        }

                        customiseSection

                        resetButton
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                    .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // Hide standard nav bar since we made a custom header
            .navigationBarHidden(true)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.fraction(0.6)])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Top Segmented Row

    private var topRowControls: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    settings.fontSize = max(0.5, (round(settings.fontSize * 10) - 1) / 10)
                }
            } label: {
                Text("A")
                    .font(.system(size: 14, weight: .regular))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(settings.fontSize <= 0.5)

            Divider().padding(.vertical, 8)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    settings.fontSize = min(2.5, (round(settings.fontSize * 10) + 1) / 10)
                }
            } label: {
                Text("A")
                    .font(.system(size: 22, weight: .regular))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(settings.fontSize >= 2.5)

            Divider().padding(.vertical, 8)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settings.layout = (settings.layout == .paginated) ? .scrolling : .paginated
                }
            } label: {
                Image(systemName: settings.layout == .paginated ? "book.pages" : "scroll")
                    .font(.system(size: 18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }

            Divider().padding(.vertical, 8)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if settings.colorTheme.isDark {
                        settings.colorTheme = .paper
                    } else {
                        settings.colorTheme = .night
                    }
                }
            } label: {
                Image(systemName: settings.colorTheme.isDark ? "sun.max" : "moon")
                    .font(.system(size: 18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
        }
        .frame(height: 48)
        .foregroundStyle(Color.primary)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Theme Grid

    private var themeGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12
        ) {
            ForEach(ReaderColorTheme.allCases, id: \.self) { theme in
                ThemeCard(
                    theme: theme,
                    font: settings.font,
                    isSelected: settings.colorTheme == theme
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        settings.colorTheme = theme
                    }
                }
            }
        }
    }

    // MARK: - Customise Section

    private var customiseSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Text Options")
                layoutOptionsCard
                    .padding(.horizontal, 20)
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Spacing")
                spacingCard
                    .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .kerning(0.8)
            .padding(.horizontal, 20)
    }

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

    private var spacingCard: some View {
        VStack(spacing: 0) {
            SliderRow(
                icon: "line.3.horizontal",
                label: "Line Height",
                value: $settings.lineHeight,
                range: 1.0...2.0,
                step: 0.1,
                format: { String(format: "%.1f", $0) }
            )
            Divider().padding(.leading, 52)
            SliderRow(
                icon: "arrow.left.and.right",
                label: "Margins",
                value: $settings.margin,
                range: 0.5...2.5,
                step: 0.1,
                format: { String(format: "%.1f×", $0) }
            )
        }
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var layoutOptionsCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $settings.justifyText) {
                Label("Justify Text", systemImage: "text.justify.leading")
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.leading, 52)

            Toggle(isOn: $settings.boldText) {
                Label("Bold Text", systemImage: "bold")
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .tint(.accentColor)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var resetButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                settings = ReaderSettings()
            }
        } label: {
            Text("Reset to Defaults")
                .font(.subheadline.bold())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 0) {
                Text("Aa")
                    .font(font.swiftUIFont(size: 26))
                    .foregroundStyle(theme.foregroundColor)
                    .frame(height: 48)

                Divider()
                    .overlay(theme.foregroundColor.opacity(0.1))

                Text(theme.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected ? theme.foregroundColor : theme.foregroundColor.opacity(0.7)
                    )
                    .frame(height: 32)
            }
            .frame(maxWidth: .infinity)
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 12))
            // Inner border for contrast on light variants
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Font Card

private struct FontCard: View {
    let font: ReaderFont
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(font.swiftUIFont(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(font.cardLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(width: 74, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                            : AnyShapeStyle(.regularMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Layout Option

private struct LayoutOption: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
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
                .font(.system(size: 13))
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
        .padding(.vertical, 12)
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
