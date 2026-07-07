import Foundation

/// Central access to environment configuration.
///
/// Values live in Info.plist (`Fathom…` keys) so changing environments is a
/// plist/xcconfig edit, not a source change. Missing or malformed keys crash
/// at first use with a clear message — the app cannot meaningfully run
/// without them, and a loud failure at launch beats a silent wrong endpoint.
enum AppConfig {

    /// Base URL of the Fathom AI backend (book ingestion + query API).
    static let backendBaseURL: URL = url(forInfoKey: "FathomBackendBaseURL")

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
}
