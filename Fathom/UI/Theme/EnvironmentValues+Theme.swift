import SwiftUI

// MARK: - EnvironmentKey

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .default
}

// MARK: - EnvironmentValues extension

extension EnvironmentValues {
    /// The active Fathom design-token set.
    ///
    /// Declare in any view:
    /// ```swift
    /// @Environment(\.appTheme) var theme
    /// ```
    /// The value is automatically provided by the `.themed()` modifier applied
    /// at the root. Previews and views not under the root still receive
    /// `AppTheme.default` via the `EnvironmentKey` default.
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
