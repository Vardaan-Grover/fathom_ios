import SwiftUI
import UIKit

/// Preview + share flow for the year card. Shows the *live* card (so the
/// editable handwritten line and format toggle update instantly), and only
/// rasterizes via `ImageRenderer` when the user actually shares.
struct ShareCardPreviewSheet: View {
    let year: Int
    let name: String
    let stats: ShareStats
    let durations: [TimeInterval]
    let columns: Int
    let theme: ShareCardTheme
    let defaultLine: String
    /// Which export shapes are offered (year card is story-only).
    var formats: [ShareCardFormat] = [.story]

    @Environment(\.dismiss) private var dismiss
    @State private var format: ShareCardFormat
    @State private var line: String
    @State private var shareImage: UIImage?
    @State private var isSharePresented = false
    @State private var isRendering = false
    @FocusState private var lineFocused: Bool

    init(year: Int, name: String, stats: ShareStats, durations: [TimeInterval],
         columns: Int, theme: ShareCardTheme, defaultLine: String,
         formats: [ShareCardFormat] = [.story]) {
        self.year = year
        self.name = name
        self.stats = stats
        self.durations = durations
        self.columns = columns
        self.theme = theme
        self.defaultLine = defaultLine
        self.formats = formats
        _format = State(initialValue: formats.first ?? .story)
        _line = State(initialValue: defaultLine)
    }

    private func card(for format: ShareCardFormat) -> YearShareCardView {
        YearShareCardView(year: year, name: name, line: line, stats: stats,
                          durations: durations, columns: columns, theme: theme, format: format)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if formats.count > 1 {
                formatPicker.padding(.bottom, 8)
            }
            preview
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        // A lighter surface than the (near-black) card, so the media stands out
        // against the sheet in dark mode.
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .sheet(isPresented: $isSharePresented) {
            if let shareImage {
                ShareSheet(items: [shareImage]).ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Share your sky")
                .font(.system(size: 22, weight: .bold, design: .serif))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.quaternarySystemFill)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var formatPicker: some View {
        Picker("Format", selection: $format) {
            ForEach(formats) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    /// The real card, laid out at render size and scaled to fill the available
    /// space — so what you see is exactly what's exported. Tapping it dismisses
    /// the keyboard.
    private var preview: some View {
        GeometryReader { geo in
            let s = format.renderSize
            let scale = min((geo.size.width - 44) / s.width, (geo.size.height - 20) / s.height)
            card(for: format)
                .frame(width: s.width, height: s.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                // Preview-only hairline (not baked into the exported image).
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .scaleEffect(scale)
                .frame(width: s.width * scale, height: s.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { lineFocused = false }
    }

    /// Note field + Share button, pinned to the bottom so both stay visible and
    /// rise above the keyboard.
    private var bottomBar: some View {
        VStack(spacing: 12) {
            TextField("a year of looking up", text: $line)
                .font(.system(size: 16, design: .serif))
                .focused($lineFocused)
                .submitLabel(.done)
                .onSubmit { lineFocused = false }
                .onChange(of: line) { _, new in
                    // Single line only.
                    if new.contains("\n") { line = new.replacingOccurrences(of: "\n", with: "") }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                .overlay(alignment: .trailing) {
                    if lineFocused {
                        Button("Done") { lineFocused = false }
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.trailing, 12)
                    }
                }

            Button {
                renderAndShare()
            } label: {
                HStack(spacing: 8) {
                    if isRendering { ProgressView().tint(.white) }
                    else { Image(systemName: "square.and.arrow.up") }
                    Text("Share")
                }
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(theme.ink))
            }
            .buttonStyle(.plain)
            .disabled(isRendering)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @MainActor private func renderAndShare() {
        lineFocused = false
        isRendering = true
        let size = format.renderSize
        let content = card(for: format).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = format.renderScale
        renderer.isOpaque = true   // card has a solid background — no alpha needed
        DispatchQueue.main.async {
            shareImage = renderer.uiImage
            isRendering = false
            if shareImage != nil { isSharePresented = true }
        }
    }
}
