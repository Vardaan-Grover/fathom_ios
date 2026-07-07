import SwiftUI

/// How a Lottie animation repeats — package-agnostic so callers don't import Lottie.
enum LottieLoop {
    case loop
    case playOnce
}

/// Whether a named Lottie animation can actually be shown right now: the Lottie
/// package is linked AND a matching `.json`/`.lottie` is bundled. Callers use this
/// to fall back to a native rendering when assets/package aren't present yet.
enum LottieAsset {
    static func available(_ name: String) -> Bool {
        guard LottieView.isAvailable else { return false }
        return Bundle.main.url(forResource: name, withExtension: "json") != nil
            || Bundle.main.url(forResource: name, withExtension: "lottie") != nil
    }
}

#if canImport(Lottie)
import Lottie
import UIKit

/// SwiftUI wrapper around a Lottie animation, with optional runtime recoloring
/// (so a stock monochrome animation is tinted to the garden's ink and adapts to
/// light/dark). Pauses automatically when off-screen / backgrounded.
struct LottieView: UIViewRepresentable {
    static let isAvailable = true

    let name: String
    var loop: LottieLoop = .loop
    var isPlaying: Bool = true
    /// When set, every color in the animation is overridden to this tint.
    var tint: Color? = nil

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name)
        view.contentMode = .scaleAspectFit
        view.loopMode = (loop == .loop) ? .loop : .playOnce
        view.backgroundBehavior = .pauseAndRestore
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        applyTint(view)
        if isPlaying { view.play() }
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        view.loopMode = (loop == .loop) ? .loop : .playOnce
        applyTint(view)
        if isPlaying, !view.isAnimationPlaying {
            view.play()
        } else if !isPlaying, view.isAnimationPlaying {
            view.pause()
        }
    }

    private func applyTint(_ view: LottieAnimationView) {
        guard let tint else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(tint).getRed(&r, green: &g, blue: &b, alpha: &a)
        let provider = ColorValueProvider(LottieColor(r: Double(r), g: Double(g), b: Double(b), a: 1))
        // "**.Color" matches every color keypath in the animation.
        view.setValueProvider(provider, keypath: AnimationKeypath(keypath: "**.Color"))
    }
}
#else

/// Lottie isn't linked yet — a no-op placeholder so the project keeps building.
/// `LottieAsset.available` returns false, so callers never actually render this.
struct LottieView: View {
    static let isAvailable = false

    let name: String
    var loop: LottieLoop = .loop
    var isPlaying: Bool = true
    var tint: Color? = nil

    var body: some View { Color.clear }
}
#endif
