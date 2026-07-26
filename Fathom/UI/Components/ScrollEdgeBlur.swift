import BlurUIKit
import SwiftUI
import UIKit

/// A progressive blur that lets scrolling content pass *under* a pinned bar
/// instead of being cut off by it.
///
/// The problem this replaces: a bar drawn on an opaque (or uniformly blurred)
/// rectangle has a hard bottom edge, and content crossing that edge disappears
/// at a visible seam. Here the blur radius ramps from full strength at the
/// pinned edge down to zero at the far edge, so text dissolves as it travels
/// under the bar rather than being clipped by it.
///
/// The ramp is *eased* rather than linear — see ``EasedEdgeBlurView`` for why —
/// so the blur wells up gradually from the far edge instead of snapping to full
/// strength as soon as content enters.
struct ScrollEdgeBlur: View {

    /// Which edge the bar is pinned to. `.top` blurs hardest at the top and
    /// clears by the bottom; `.bottom` is the mirror, for the tab bar.
    enum Edge {
        case top
        case bottom

        var direction: VariableBlurView.Direction {
            // BlurUIKit names these by the direction the gradient *flows*:
            // `.down` is its status-bar case (full blur at the top edge,
            // fading downward) and `.up` its toolbar case.
            switch self {
            case .top: return .down
            case .bottom: return .up
            }
        }
    }

    let edge: Edge
    var maximumBlurRadius: CGFloat = 9
    /// Fraction of the height pinned at a *constant* maximum blur before the
    /// ramp begins, measured from the pinned edge.
    ///
    /// `nil` — the default — ramps continuously across the whole height, so the
    /// blur is at its weakest where content enters and strengthens all the way
    /// to the edge. Give this a value only to buy contrast under the bar's own
    /// contents, at the cost of a flat-looking slab at the top.
    var fullStrengthFraction: CGFloat? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        EasedEdgeBlur(
            direction: edge.direction,
            maximumBlurRadius: maximumBlurRadius,
            // BlurUIKit's `blurStartingInset` is the plateau length: the blur
            // holds at maximum for this fraction from the pinned edge before it
            // begins to ramp.
            blurStartingInset: fullStrengthFraction.map { .relative(fraction: $0) },
            // The tint is the theme background — near-white parchment in light
            // mode — and it peaks at the pinned edge. Keep the alpha low: a high
            // value paints a solid pale strip across the top rather than reading
            // as depth. It exists only to keep the status bar legible over a busy
            // cover; the blur does the real separating.
            dimmingColor: theme.colors.background
        )
        .allowsHitTesting(false)
    }
}

extension View {
    /// Pins the standard progressive top-edge blur over this screen, so scrolling
    /// content dissolves under the status bar instead of being clipped at a hard
    /// line. This is the single definition every top-level tab uses — the library
    /// screens, Vocabulary, and Profile — so the treatment stays identical.
    ///
    /// Apply it to a screen's scrolling content (the `ScrollView`/`List`, or the
    /// container that holds it). The blur reaches full strength at the very top
    /// and clears by `height` points down.
    ///
    /// - Parameter height: How far the blur extends down from the top edge. The
    ///   status-bar inset eats the first ~59pt, so the default leaves only a
    ///   short fade into content. Bump it for a taller, softer transition.
    func topScrollEdgeBlur(height: CGFloat = 58) -> some View {
        overlay(alignment: .top) {
            ScrollEdgeBlur(edge: .top)
                .frame(height: height)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Bridges BlurUIKit's ``VariableBlurView`` into SwiftUI while bending its
/// (linear) radius ramp into an ease-in.
///
/// BlurUIKit only ever builds its blur mask as a straight linear ramp: the
/// sine easing it ships (`easeInOutSine`) is wired to the *dimming* gradient
/// alone, with no public hook to borrow it for the blur. A linear radius ramp
/// reads as "full strength almost immediately," because perceived blur climbs
/// fast off the low end. Multiplying it by a smoothstep alpha mask — flat slope
/// at both ends — bends the *perceived* curve into an ease-in, so the blur wells
/// up gradually from the far edge instead of snapping on.
///
/// The mask is a `CAGradientLayer` set on the blur view's own layer, not a
/// SwiftUI `.mask`: the latter rasterizes the view offscreen and severs its live
/// backdrop sampling, collapsing the blur to nothing. A layer mask leaves the
/// backdrop filter intact. Radius and mask fall together toward the far edge
/// (both near zero there), so the fade never leaves a partially-blurred ghost of
/// the sharp text beneath it.
private struct EasedEdgeBlur: UIViewRepresentable {
    let direction: VariableBlurView.Direction
    let maximumBlurRadius: CGFloat
    let blurStartingInset: VariableBlurView.GradientSizing?
    let dimmingColor: Color

    func makeUIView(context: Context) -> EasedEdgeBlurView {
        let view = EasedEdgeBlurView()
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: EasedEdgeBlurView, context: Context) {
        apply(to: uiView)
    }

    private func apply(to view: EasedEdgeBlurView) {
        view.configure(
            direction: direction,
            maximumBlurRadius: maximumBlurRadius,
            blurStartingInset: blurStartingInset,
            dimmingColor: UIColor(dimmingColor)
        )
    }
}

/// Hosts a ``VariableBlurView`` and masks its layer with a smoothstep alpha
/// ramp. A container is used rather than a subclass because `VariableBlurView`
/// is `public`, not `open`, so it can't be subclassed across modules — but its
/// layer is ours to mask.
final class EasedEdgeBlurView: UIView {

    private let blur = VariableBlurView()
    private let rampMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The blur itself already ignores touches; keep the container inert too
        // so content underneath stays interactive.
        isUserInteractionEnabled = false
        addSubview(blur)

        // A white-to-clear ramp whose alpha follows a smoothstep curve. White
        // keeps the blur; clear hides it. The eased stops are what make the blur
        // build up slowly instead of climbing linearly.
        rampMask.colors = Self.easedAlphas.map { UIColor(white: 1, alpha: $0).cgColor }
        rampMask.locations = Self.easedAlphas.indices.map {
            NSNumber(value: Double($0) / Double(Self.easedAlphas.count - 1))
        }
        blur.layer.mask = rampMask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        direction: VariableBlurView.Direction,
        maximumBlurRadius: CGFloat,
        blurStartingInset: VariableBlurView.GradientSizing?,
        dimmingColor: UIColor
    ) {
        blur.direction = direction
        blur.maximumBlurRadius = maximumBlurRadius
        blur.blurStartingInset = blurStartingInset
        blur.dimmingTintColor = dimmingColor
        blur.dimmingAlpha = .interfaceStyle(lightModeAlpha: 0.22, darkModeAlpha: 0.14)
        // No overshoot: it draws the tint outside the view's bounds, which would
        // be clipped by our layer mask anyway and only widens the pale strip.
        blur.dimmingOvershoot = nil

        // Orient the ramp so it is opaque at the pinned edge and clear at the
        // far edge, matching the blur's own flow direction.
        let (start, end): (CGPoint, CGPoint)
        switch direction {
        case .down:  (start, end) = (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        case .up:    (start, end) = (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0))
        case .right: (start, end) = (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        case .left:  (start, end) = (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5))
        @unknown default: (start, end) = (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        }
        rampMask.startPoint = start
        rampMask.endPoint = end
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        // The mask lives in the blur view's coordinate space; resize it in step
        // without the implicit animation a layout pass would otherwise give it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rampMask.frame = blur.bounds
        CATransaction.commit()
    }

    /// Smoothstep (`3t²−2t³`) sampled from the pinned edge (opaque, α=1) to the
    /// far edge (clear, α=0). The flat slope at both ends is what turns the
    /// blur's linear radius ramp into a gradual ease-in.
    private static let easedAlphas: [CGFloat] = stride(from: 0.0, through: 1.0, by: 0.125).map { t in
        let s = t * t * (3 - 2 * t)   // 0 at the pinned edge … 1 at the far edge
        return 1 - s
    }
}
