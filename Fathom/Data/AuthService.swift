import Foundation
import Combine
import Auth

// Global auth client — initialized once, shared across the app and backend layer.
// AuthClient is Sendable, so this is safe to access from any concurrency context.
let supabase = AuthClient(
    configuration: AuthClient.Configuration(
        url: URL(string: "https://igueynbdkxwrqpknvxfv.supabase.co/auth/v1")!,
        headers: [
            "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlndWV5bmJka3h3cnFwa252eGZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc3NzY5MjEsImV4cCI6MjA5MzM1MjkyMX0.e_JlRuHVuCIANNe0bECjaK_GLK26xcSZDNeLOgZBdNk"
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
