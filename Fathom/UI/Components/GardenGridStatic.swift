import SwiftUI

/// A static, fully-settled render of the garden grid — the same dot + doodle
/// layout as the live Canvas, but built from plain positioned views so it
/// rasterizes cleanly through `ImageRenderer` (no animation, no `@Environment`).
/// Used by the share cards.
struct GardenGridStatic: View {
    /// Reading time per day (today/future already zeroed by the caller).
    let durations: [TimeInterval]
    let ink: Color
    var columns: Int = 14

    var body: some View {
        GeometryReader { geo in
            let dots = buildDotGrid(count: durations.count, size: geo.size, columns: columns)
            let doodles = buildDoodleSprites(durations: durations, size: geo.size, columns: columns)

            ZStack(alignment: .topLeading) {
                ForEach(Array(dots.enumerated()), id: \.offset) { _, sprite in
                    if case .dot(let radius, let opacity) = sprite.kind {
                        Circle()
                            .fill(ink.opacity(opacity))
                            .frame(width: radius * 2, height: radius * 2)
                            .position(sprite.center)
                    }
                }
                ForEach(Array(doodles.enumerated()), id: \.offset) { _, sprite in
                    if case .doodle(let name, _) = sprite.kind {
                        Image(name)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(ink)
                            .frame(width: sprite.baseDim, height: sprite.baseDim)
                            .position(sprite.center)
                    }
                }
            }
        }
    }
}
