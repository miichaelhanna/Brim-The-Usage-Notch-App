import Foundation

/// Notices when a credential has been written again since the copy that failed.
///
/// A lapsed login is not something this app can mend: only the tool that owns it can
/// sign in again. What it can do is stop making the user wait once that has happened,
/// and the evidence is a date rather than a secret — when the item was last written.
///
/// The first sighting never counts. That one is the credential whose failure put the
/// app in this state, and treating it as news would retry immediately, fail again, and
/// do it forever.
public struct CredentialRenewal: Equatable, Sendable {
    private var seen: Date?
    private var hasLooked = false

    public init() {}

    /// True exactly once for each write after the first look.
    public mutating func noticed(_ changedAt: Date?) -> Bool {
        defer { seen = changedAt; hasLooked = true }
        guard hasLooked else { return false }
        guard let changedAt else { return false }
        // Nothing there a moment ago and something there now is a new login too: a
        // tool that was signed out and has just signed back in writes its first item.
        guard let seen else { return true }
        // Different, not merely newer. An item restored from a backup carries an older
        // date than the one that failed and is still a different credential, worth the
        // one attempt this returns.
        return changedAt != seen
    }

    /// Forgets what it has seen, for a connection that is being started over.
    public mutating func reset() { self = CredentialRenewal() }
}
