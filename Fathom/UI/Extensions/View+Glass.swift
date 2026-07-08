import SwiftUI

extension View {
    /// Liquid-glass capsule background on iOS 26+, ultra-thin material before.
    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: .capsule)
        }
    }
}

/// A shape rendered as liquid glass on iOS 26+, ultra-thin material before.
/// For use inside `.background(...)`.
@ViewBuilder
func glassFill(_ shape: some Shape) -> some View {
    if #available(iOS 26, *) {
        shape.glassEffect(.regular)
    } else {
        shape.fill(.ultraThinMaterial)
    }
}
