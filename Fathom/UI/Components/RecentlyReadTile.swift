import SwiftUI

struct RecentlyReadTile: View {
    let book: HomeBook
    let progress: Double
    let onTap: () -> Void

    @State private var dominantColors: [Color] = []

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                meshBackground
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 12) {
                    coverView
                    infoView
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .task { await loadColors() }
    }

    // MARK: - Background

    @ViewBuilder
    private var meshBackground: some View {
        if dominantColors.count >= 4 {
            TimelineView(.animation(minimumInterval: 1 / 24)) { ctx in
                let t = Float(ctx.date.timeIntervalSinceReferenceDate)
                MeshGradient(
                    width: 3, height: 3,
                    points: animatedPoints(t: t),
                    colors: meshColors(from: dominantColors)
                )
            }
            .overlay(Color.black.opacity(0.22))
        } else {
            (book.coverColor ?? Color.accentColor)
                .overlay(Color.black.opacity(0.3))
        }
    }

    // MARK: - Cover

    private var coverView: some View {
        Group {
            if let uiImage = BookFileStore.coverImage(for: book.coverFilename) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 80)
                    .clipped()
            } else {
                (book.coverColor ?? Color.accentColor)
                    .frame(width: 56, height: 80)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.28), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 10),
                        alignment: .leading
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.35), radius: 6, x: 2, y: 3)
    }

    // MARK: - Info

    private var infoView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Continue Reading")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.8)
                .textCase(.uppercase)

            Text(book.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(book.author)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 2)

            progressView
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: 3)
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: geo.size.width * max(0.015, progress), height: 3)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Mesh helpers

    private func animatedPoints(t: Float) -> [SIMD2<Float>] {
        let a: Float = 0.10
        let s = t * 0.22
        return [
            [0, 0],
            [0.5 + a * sin(s * 1.3), 0],
            [1, 0],
            [0, 0.5 + a * sin(s * 1.1)],
            [0.5 + a * sin(s * 0.8), 0.5 + a * cos(s * 1.2)],
            [1, 0.5 + a * sin(s * 0.9)],
            [0, 1],
            [0.5 + a * sin(s * 1.1), 1],
            [1, 1],
        ]
    }

    private func meshColors(from colors: [Color]) -> [Color] {
        guard colors.count >= 4 else {
            return Array(repeating: colors.first ?? .blue, count: 9)
        }
        let c = colors
        return [
            c[0], blend(c[0], c[1], 0.5), c[1],
            blend(c[0], c[2], 0.5), blend(c[2], c[3], 0.4), blend(c[1], c[3], 0.5),
            c[2], blend(c[2], c[3], 0.5), c[3],
        ]
    }

    private func blend(_ a: Color, _ b: Color, _ t: CGFloat) -> Color {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t
        )
    }

    // MARK: - Color loading

    @MainActor
    private func loadColors() async {
        let coverFilename = book.coverFilename
        let coverColor = book.coverColor
        let extracted = await Task.detached(priority: .userInitiated) {
            if let image = BookFileStore.coverImage(for: coverFilename) {
                return extractDominantColors(from: image, count: 4)
            } else {
                return deriveColors(from: coverColor ?? .blue)
            }
        }.value
        withAnimation(.easeIn(duration: 0.6)) {
            dominantColors = extracted
        }
    }
}

// MARK: - Color extraction

private func extractDominantColors(from image: UIImage, count: Int) -> [Color] {
    let size = CGSize(width: 10, height: 10)
    let renderer = UIGraphicsImageRenderer(size: size)
    let small = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }

    guard let cgImage = small.cgImage else { return deriveColors(from: .blue) }

    let w = cgImage.width
    let h = cgImage.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    guard
        let ctx = CGContext(
            data: &raw, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return deriveColors(from: .blue) }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

    struct Px { let h, s, b, r, g, bl: CGFloat }
    var pixels: [Px] = []

    for i in stride(from: 0, to: raw.count, by: 4) {
        let alpha = CGFloat(raw[i + 3]) / 255
        guard alpha > 0.5 else { continue }
        let r = CGFloat(raw[i]) / 255
        let g = CGFloat(raw[i + 1]) / 255
        let bl = CGFloat(raw[i + 2]) / 255
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var a: CGFloat = 0
        UIColor(red: r, green: g, blue: bl, alpha: 1).getHue(
            &hue, saturation: &sat, brightness: &bri, alpha: &a)
        guard bri > 0.12, bri < 0.94, sat > 0.10 else { continue }
        pixels.append(Px(h: hue, s: sat, b: bri, r: r, g: g, bl: bl))
    }

    guard !pixels.isEmpty else { return deriveColors(from: .blue) }

    let sorted = pixels.sorted { $0.s * $0.b > $1.s * $1.b }
    var selected: [Px] = []
    for p in sorted {
        let tooClose = selected.contains { ex in
            let d = abs(p.h - ex.h)
            return min(d, 1 - d) < 0.07
        }
        if !tooClose { selected.append(p) }
        if selected.count >= count { break }
    }

    while selected.count < count {
        selected.append(selected[selected.count % max(1, selected.count)])
    }

    return selected.map { Color(red: $0.r, green: $0.g, blue: $0.bl) }
}

private func deriveColors(from base: Color) -> [Color] {
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    UIColor(base).getHue(&h, saturation: &s, brightness: &b, alpha: &a)

    return [
        Color(UIColor(hue: h, saturation: s, brightness: b, alpha: 1)),
        Color(
            UIColor(
                hue: fmod(h + 0.06, 1), saturation: max(0.1, s - 0.20),
                brightness: min(1, b + 0.22), alpha: 1)),
        Color(
            UIColor(
                hue: fmod(h + 0.13, 1), saturation: min(1, s + 0.10),
                brightness: max(0.2, b - 0.12), alpha: 1)),
        Color(
            UIColor(
                hue: fmod(h + 0.50, 1), saturation: max(0.1, s - 0.25),
                brightness: min(1, b + 0.15), alpha: 1)),
    ]
}

// MARK: - Preview

#Preview {
    RecentlyReadTile(
        book: HomeBook(
            id: UUID(),
            title: "Crime and Punishment",
            author: "Fyodor Dostoevsky",
            coverColor: Color(hex: "1A5EA8"),
            textColor: .white,
            coverFilename: nil
        ),
        progress: 0.12,
        onTap: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
