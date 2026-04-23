import SwiftUI
import Combine

// MARK: - ThemeManager

/// Manages the app's active theme and the user's color-scheme preference.
///
/// **Injected at the root** via `.themed()` and read anywhere via:
/// ```swift
/// @Environment(\.appTheme) var theme
/// ```
///
/// The `colorSchemeOverride` property lets users (or future Settings screens)
/// pin the app to Light or Dark regardless of the system setting. When `nil`,
/// the system's current appearance is used.
@MainActor
final class ThemeManager: ObservableObject {

    // MARK: Published state

    /// The resolved set of design tokens. Always `AppTheme.default` for now;
    /// becomes the switch point if multiple palettes are introduced.
    @Published private(set) var current: AppTheme = .default

    /// Overrides the device's appearance. `nil` = follow system (default).
    /// Persisted across launches via UserDefaults.
    @Published var colorSchemeOverride: ColorScheme? {
        didSet { persistPreference() }
    }

    // MARK: Init

    init() {
        colorSchemeOverride = Self.loadPersistedPreference()
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "readora.themeManager.colorSchemeOverride"

    private func persistPreference() {
        switch colorSchemeOverride {
        case .light:  UserDefaults.standard.set("light", forKey: Self.userDefaultsKey)
        case .dark:   UserDefaults.standard.set("dark",  forKey: Self.userDefaultsKey)
        case .none:   UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        @unknown default: break
        }
    }

    private static func loadPersistedPreference() -> ColorScheme? {
        switch UserDefaults.standard.string(forKey: userDefaultsKey) {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
