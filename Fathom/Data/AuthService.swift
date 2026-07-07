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
                if let s = newSession { await handleSignIn(session: s) }
            case .signedIn, .tokenRefreshed:
                session = newSession
                if let s = newSession { await handleSignIn(session: s) }
            case .signedOut:
                session = nil
                handleSignOut()
            default:
                break
            }
        }
    }

    // MARK: - Private helpers

    private func handleSignIn(session: Session) async {
        guard let userID = UUID(uuidString: session.user.id.uuidString) else { return }

        // 1. Configure file store first (must happen before migration or any file access).
        ICloudFileStore.shared.configure(userID: userID)

        // 2. Start the iCloud download monitor on the main actor.
        await MainActor.run {
            ICloudDownloadMonitor.shared.start()
        }

        // 3. Migrate existing local files into iCloud on first launch.
        await LocalToICloudMigration.shared.migrateIfNeeded()

        // 4. Start the CloudKit sync engine (push path).
        //    Skipped gracefully if iCloud isn't available (Personal Team, no entitlement).
        if ICloudFileStore.shared.isAvailable {
            await SyncEngine.shared.start(userID: userID)
        }
    }

    private func handleSignOut() {
        ICloudFileStore.shared.reset()
        Task {
            await SyncEngine.shared.stop()
            await MainActor.run {
                ICloudDownloadMonitor.shared.stop()
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
