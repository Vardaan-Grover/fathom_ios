import Foundation

/// Central access to environment configuration.
///
/// Values live in Info.plist (`Fathom…` keys) so changing environments is a
/// plist/xcconfig edit, not a source change. Keys the app cannot run without
/// crash at first use with a clear message — a loud failure beats a silent
/// wrong endpoint.
enum AppConfig {

    /// Base URL of the Fathom AI backend (book ingestion + query API).
    ///
    /// Optional, unlike the Supabase values: there is no deployed backend yet,
    /// and the AI companion that would call it is disabled
    /// (`FeatureFlags.aiCompanionEnabled`). Shipping a placeholder endpoint
    /// would be worse than shipping none — this key previously held a
    /// developer's LAN address, which went into every build of a feature no
    /// user can reach.
    ///
    /// To point a local build at a backend, pass a launch argument in the
    /// scheme rather than editing the tracked Info.plist:
    ///
    ///     -FathomBackendBaseURL http://192.168.1.10:8080
    ///
    /// Set the Info.plist key instead once a real environment exists.
    static let backendBaseURL: URL? = optionalURL(forKey: "FathomBackendBaseURL")

    /// Supabase auth endpoint.
    static let supabaseAuthURL: URL = url(forInfoKey: "FathomSupabaseAuthURL")

    /// Supabase anon (publishable) key. Not a secret — it identifies the
    /// project and is safe to ship — but it belongs in config, not code.
    static let supabaseAnonKey: String = string(forInfoKey: "FathomSupabaseAnonKey")

    // MARK: - Private

    private static func string(forInfoKey key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            preconditionFailure("Missing Info.plist configuration key: \(key)")
        }
        return value
    }

    private static func url(forInfoKey key: String) -> URL {
        guard let url = URL(string: string(forInfoKey: key)) else {
            preconditionFailure("Info.plist key \(key) is not a valid URL")
        }
        return url
    }

    /// Launch argument first (so a scheme can override without touching the
    /// bundle), then Info.plist, then nil.
    private static func optionalURL(forKey key: String) -> URL? {
        let raw = UserDefaults.standard.string(forKey: key)
            ?? Bundle.main.object(forInfoDictionaryKey: key) as? String
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}
