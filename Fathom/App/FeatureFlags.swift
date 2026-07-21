import Foundation

/// Compile-time switches for features that live in the codebase but are not
/// currently user-facing.
enum FeatureFlags {
    /// AI Reading Companion: passage chat, backend ingestion, and conversation
    /// sync. The UI entry points (import AI step, Ask AI menu action, AI chats
    /// button, book-details status chip) are commented out at their call sites;
    /// this flag additionally disables the background paths (CloudKit
    /// conversation sync, backend ingestion polling) so the dormant feature
    /// does no work. Flip to true when the feature ships again.
    static let aiCompanionEnabled = false

    /// Supabase accounts: the magic-link sign-in wall and the Profile sign-out
    /// row.
    ///
    /// Off for v1. Reading, the sky, and vocabulary are entirely local, and
    /// iCloud sync is scoped by Apple ID rather than by Fathom account, so
    /// nothing user-facing needs a sign-in. The wall only ever gated the AI
    /// companion's bearer token, which is itself dormant. `AuthService` and
    /// the sign-in screens stay in the tree so this can be flipped back on
    /// when the backend ships.
    ///
    /// Sync identity no longer derives from the Supabase user — see
    /// `SyncBootstrap`.
    static let accountsEnabled = false
}
