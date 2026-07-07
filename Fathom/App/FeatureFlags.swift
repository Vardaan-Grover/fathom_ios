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
}
