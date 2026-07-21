import SwiftUI

struct FolderStickerEditSheet: View {
    let category: HomeCategory
    let initialStickers: (String, String)
    var onSave: (_ s1: String, _ s2: String) -> Void
    
    @State private var s1: String
    @State private var s2: String
    @State private var activeSticker: Int = 1

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) var theme
    
    init(category: HomeCategory, initialStickers: (String, String), onSave: @escaping (String, String) -> Void) {
        self.category = category
        self.initialStickers = initialStickers
        self.onSave = onSave
        self._s1 = State(initialValue: initialStickers.0)
        self._s2 = State(initialValue: initialStickers.1)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                // Large Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(category.shelfColor.opacity(0.1))
                    
                    folderPreview
                        .frame(width: 200)
                }
                .frame(height: 200)
                .padding(.top, 16)
                .padding(.horizontal, 24)

                // Instructions
                VStack(spacing: 8) {
                    Text("Tap a sticker on the folder, then pick an emoji.")
                        .font(theme.typography.headline)
                        .foregroundColor(theme.colors.primary)

                    Text("Or randomize them if you're feeling lucky.")
                        .font(theme.typography.subheadline)
                        .foregroundColor(theme.colors.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                // Randomize Button
                Button {
                    let pairs = StickerStore.allPairs
                    if let pair = pairs.randomElement() {
                        withAnimation(.spring(response: 0.3)) {
                            s1 = pair.0
                            s2 = pair.1
                        }
                    }
                } label: {
                    Label("Randomize", systemImage: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 24)

                // Feeds whichever sticker slot is currently selected.
                EmojiGridPicker(selection: activeSticker == 1 ? $s1 : $s2)
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 12)
            }
            .navigationTitle("Edit Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(s1, s2)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
    
    private var folderPreview: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w / 1.2
            
            VStack {
                Spacer()
                ZStack(alignment: .bottom) {
                    // Back
                    Path { path in
                        let tabWidth = w * 0.45
                        let tabHeight = h * 0.18
                        let radius: CGFloat = 8
                        path.move(to: CGPoint(x: radius, y: 0))
                        path.addLine(to: CGPoint(x: tabWidth - radius, y: 0))
                        path.addQuadCurve(to: CGPoint(x: tabWidth + radius, y: tabHeight), control: CGPoint(x: tabWidth, y: 0))
                        path.addLine(to: CGPoint(x: w - radius, y: tabHeight))
                        path.addQuadCurve(to: CGPoint(x: w, y: tabHeight + radius), control: CGPoint(x: w, y: tabHeight))
                        path.addLine(to: CGPoint(x: w, y: h - radius))
                        path.addQuadCurve(to: CGPoint(x: w - radius, y: h), control: CGPoint(x: w, y: h))
                        path.addLine(to: CGPoint(x: radius, y: h))
                        path.addQuadCurve(to: CGPoint(x: 0, y: h - radius), control: CGPoint(x: 0, y: h))
                        path.addLine(to: CGPoint(x: 0, y: radius))
                        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: 0))
                    }
                    .fill(Color.gray.opacity(0.2))
                    
                    // Front flap
                    folderFront
                        .frame(height: h * 0.6)
                }
                .frame(width: w, height: h)
                Spacer()
            }
        }
    }
    
    private var folderFront: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(category.shelfColor.opacity(0.12))
                
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                
                VStack(spacing: 2) {
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.04))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                
                // S1
                ZStack {
                    if activeSticker == 1 {
                        Circle()
                            .fill(theme.colors.primary.opacity(0.1))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle().strokeBorder(theme.colors.primary.opacity(0.5), lineWidth: 2)
                            )
                    }
                    Text(s1.isEmpty ? "1️⃣" : s1)
                        .font(.system(size: 34))
                        .background(Color.white.clipShape(Circle()).padding(-3))
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                }
                .rotationEffect(.degrees(-10))
                .position(x: w * 0.28, y: h * 0.4)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        activeSticker = 1
                    }
                }
                
                // S2
                ZStack {
                    if activeSticker == 2 {
                        Circle()
                            .fill(theme.colors.primary.opacity(0.1))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle().strokeBorder(theme.colors.primary.opacity(0.5), lineWidth: 2)
                            )
                    }
                    Text(s2.isEmpty ? "2️⃣" : s2)
                        .font(.system(size: 34))
                        .background(Color.white.clipShape(Circle()).padding(-3))
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                }
                .rotationEffect(.degrees(14))
                .position(x: w * 0.72, y: h * 0.6)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        activeSticker = 2
                    }
                }
            }
        }
    }
}
