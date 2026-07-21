import Foundation
import Combine
import Auth

// Global auth client — initialized once, shared across the app and backend layer.
// AuthClient is Sendable, so this is safe to access from any concurrency context.
// Endpoint + key come from Info.plist via AppConfig.
let supabase = AuthClient(
    configuration: AuthClient.Configuration(
        url: AppConfig.supabaseAuthURL,
        headers: [
            "apikey": AppConfig.supabaseAnonKey
        ],
        flowType: .implicit,
        localStorage: KeychainLocalStorage(),
        logger: nil,
        emitLocalSessionAsInitialSession: true,
    )
)

final class AuthService: ObservableObject {
    @Published var session: Session? = nil
    @Published var isLoading = true

    // Long-running listener — call once with .task {} at app root.
    // Handles initial session restore from Keychain (.initialSession fires immediately,
    // no network required) and all subsequent state changes.
    func startListening() async {
        for await (event, newSession) in supabase.authStateChanges {
            switch event {
            case .initialSession:
                session = newSession
                isLoading = false
            case .signedIn, .tokenRefreshed:
                session = newSession
            case .signedOut:
                session = nil
            default:
                break
            }
        }
    }

    // Note: this service no longer starts or stops iCloud sync. Storage and
    // CloudKit are scoped by Apple ID and are brought up at launch by
    // `SyncBootstrap`, independent of whether a Fathom account exists —
    // signing out must not detach a user from their own synced library.

    func sendMagicLink(email: String) async throws {
        try await supabase.signInWithOTP(
            email: email,
            shouldCreateUser: true
        )
    }

    // Called from .onOpenURL — extracts tokens from fathom://auth/callback and
    // stores the session in Keychain. The authStateChanges stream fires .signedIn next.
    func handleDeepLink(_ url: URL) async throws {
        try await supabase.session(from: url)
    }

    func signOut() async throws {
        try await supabase.signOut()
    }
}
