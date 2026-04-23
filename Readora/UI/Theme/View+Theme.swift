import SwiftUI

// MARK: - View convenience

extension View {

    /// Wires the `ThemeManager` into the SwiftUI environment.
    ///
    /// Call **once at the root** of your view hierarchy (inside `ReadoraApp.body`):
    /// ```swift
    /// RootView(...)
    ///     .themed(with: themeManager)
    /// ```
    ///
    /// This does two things:
    /// 1. Injects `themeManager.current` as `\.appTheme` so every descendant
    ///    can read design tokens via `@Environment(\.appTheme) var theme`.
    /// 2. Applies `preferredColorScheme(_:)` so the app respects the stored
    ///    user override (or follows the device if the override is `nil`).
    func themed(with manager: ThemeManager) -> some View {
        self
            .environment(\.appTheme, manager.current)
            .preferredColorScheme(manager.colorSchemeOverride)
    }
}
