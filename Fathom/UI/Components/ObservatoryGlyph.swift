import SwiftUI

/// A bespoke, dependency-free "sky-window" emblem for the home observatory. A
/// glassy lens holds a tiny celestial scene drawn in one frame-capped Canvas:
/// twinkling stars always, a sweeping searchlight beam while *spotting*, and a
/// blooming, pulsing spark while a doodle is *pending*. Everything tints to the
/// garden's ink, so it stays on-brand in light and dark.
struct ObservatoryGlyph: View {
    let phase: ObservatoryViewModel.Phase
    let ink: Color
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme

    private let fps = 1.0 / 30.0

    // A curated (not random) constellation so it always looks composed.
    private let stars: [Star] = [
        Star(x: -0.48, y: -0.34, r: 0.9, phase: 0.0, speed: 1.1),
        Star(x:  0.42, y: -0.52, r: 1.2, phase: 1.6, speed: 0.8),
        Star(x:  0.56, y:  0.10, r: 0.8, phase: 3.1, speed: 1.4),
        Star(x: -0.60, y:  0.16, r: 0.7, phase: 2.2, speed: 1.0),
        Star(x:  0.08, y: -0.14, r: 0.6, phase: 4.0, speed: 1.7),
        Star(x: -0.18, y:  0.44, r: 0.7, phase: 0.8, speed: 1.2),
    ]

    var body: some View {
        ZStack {
            lens
            sceneCanvas.clipShape(Circle())

            // The telescope anchors the identity, sitting low in the lens.
            Image("Telescope")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(ink)
                .frame(width: 20, height: 20)
                .opacity(phase == .idle ? 0.5 : 0.9)
                .offset(y: 9)

            if phase == .pending { badge }
        }
    }

    // MARK: Lens

    private var lens: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        ink.opacity(colorScheme == .dark ? 0.24 : 0.13),
                        ink.opacity(colorScheme == .dark ? 0.10 : 0.05),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(Circle().stroke(ink.opacity(0.25), lineWidth: 1))
    }

    private var badge: some View {
        Circle()
            .fill(ink)
            .frame(width: 14, height: 14)
            .overlay(
                Image(systemName: "sparkle")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            )
            .offset(x: 17, y: -17)
    }

    // MARK: Scene

    @ViewBuilder private var sceneCanvas: some View {
        if reduceMotion {
            Canvas { context, size in draw(context, size: size, t: 0) }
        } else {
            TimelineView(.animation(minimumInterval: fps)) { timeline in
                Canvas { context, size in
                    draw(context, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    private func draw(_ context: GraphicsContext, size: CGSize, t: Double) {
        drawStars(context, size: size, t: t)
        if phase == .spotting { drawBeam(context, size: size, t: t) }
        if phase == .pending { drawSpark(context, size: size, t: t) }
    }

    private func drawStars(_ context: GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = size.width * 0.5
        let active = phase != .idle
        let unit = size.width / 46
        for s in stars {
            let twinkle = active
                ? 0.25 + 0.75 * (0.5 + 0.5 * sin(t * s.speed + s.phase))
                : 0.5
            let p = CGPoint(x: center.x + CGFloat(s.x) * scale * 0.82,
                            y: center.y + CGFloat(s.y) * scale * 0.82)
            let r = CGFloat(s.r) * unit
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                with: .color(ink.opacity(twinkle))
            )
        }
    }

    /// A soft searchlight fanning up from the telescope, panning left↔right.
    private func drawBeam(_ context: GraphicsContext, size: CGSize, t: Double) {
        let apex = CGPoint(x: size.width / 2, y: size.height * 0.82)
        let angle = -Double.pi / 2 + sin(t * 0.9) * (Double.pi / 5)   // pan ±36°
        let half = Double.pi / 10                                     // 18° spread
        let len = size.width * 0.72

        func point(_ a: Double) -> CGPoint {
            CGPoint(x: apex.x + CGFloat(cos(a)) * len, y: apex.y + CGFloat(sin(a)) * len)
        }
        var beam = Path()
        beam.move(to: apex)
        beam.addLine(to: point(angle - half))
        beam.addLine(to: point(angle + half))
        beam.closeSubpath()

        context.fill(
            beam,
            with: .radialGradient(
                Gradient(colors: [ink.opacity(0.38), .clear]),
                center: apex, startRadius: 0, endRadius: len
            )
        )
    }

    /// A blooming, pulsing spark high in the lens — "there's something up there."
    private func drawSpark(_ context: GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.34)
        let pulse = 0.5 + 0.5 * sin(t * 2.2)

        // Halo.
        let haloR = size.width * (0.20 + 0.06 * pulse)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - haloR, y: center.y - haloR,
                                   width: haloR * 2, height: haloR * 2)),
            with: .radialGradient(
                Gradient(colors: [ink.opacity(0.35 + 0.25 * pulse), .clear]),
                center: center, startRadius: 0, endRadius: haloR
            )
        )

        // Four-point star.
        let outer = size.width * (0.16 + 0.03 * pulse)
        context.fill(fourPointStar(center: center, outer: outer, inner: outer * 0.34),
                     with: .color(ink.opacity(0.9)))
    }

    private func fourPointStar(center: CGPoint, outer: CGFloat, inner: CGFloat) -> Path {
        var path = Path()
        for i in 0..<8 {
            let r = (i % 2 == 0) ? outer : inner
            let a = Double(i) * .pi / 4 - .pi / 2
            let p = CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    struct Star {
        let x, y, r, phase, speed: Double
    }
}
