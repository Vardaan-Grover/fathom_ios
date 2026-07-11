import SwiftUI
import UIKit

/// Reusable preview + share machinery for every card type: the sheet chrome, the
/// Story/Square toggle, the live (scaled) preview, keyboard-safe bottom bar with
/// card-specific `controls`, and the render-on-share via `ImageRenderer`.
/// A concrete card just supplies its `card(format)` view and any `controls`.
struct ShareCardScaffold<Card: View, Controls: View>: View {
    let title: String
    let formats: [ShareCardFormat]
    /// Accent for the Share button.
    let ink: Color
    private let cardBuilder: (ShareCardFormat) -> Card
    private let controlsBuilder: () -> Controls

    @Environment(\.dismiss) private var dismiss
    @State private var format: ShareCardFormat
    @State private var shareImage: UIImage?
    @State private var isSharePresented = false
    @State private var isRendering = false

    init(title: String,
         formats: [ShareCardFormat],
         ink: Color,
         @ViewBuilder controls: @escaping () -> Controls = { EmptyView() },
         @ViewBuilder card: @escaping (ShareCardFormat) -> Card) {
        self.title = title
        self.formats = formats
        self.ink = ink
        self.controlsBuilder = controls
        self.cardBuilder = card
        _format = State(initialValue: formats.first ?? .story)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if formats.count > 1 { formatPicker.padding(.bottom, 8) }
            preview
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        // Lighter than the (often near-black) card so the media stands out.
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
            Text(title)
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

    /// The real card at render size, scaled to fill — what you see is exported.
    private var preview: some View {
        GeometryReader { geo in
            let s = format.renderSize
            let scale: CGFloat = {
                let w = (geo.size.width - 44) / s.width
                let h = (geo.size.height - 20) / s.height
                let val = min(w, h)
                return val.isFinite && val > 0 ? val : 0
            }()
            cardBuilder(format)
                .frame(width: s.width, height: s.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        .onTapGesture { endEditing() }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            controlsBuilder()

            Button { renderAndShare() } label: {
                HStack(spacing: 8) {
                    if isRendering { ProgressView().tint(.white) }
                    else { Image(systemName: "square.and.arrow.up") }
                    Text("Share")
                }
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(ink))
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
        endEditing()
        isRendering = true
        let size = format.renderSize
        let content = cardBuilder(format).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = format.renderScale
        renderer.isOpaque = true
        DispatchQueue.main.async {
            shareImage = renderer.uiImage
            isRendering = false
            if shareImage != nil { isSharePresented = true }
        }
    }

    private func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
