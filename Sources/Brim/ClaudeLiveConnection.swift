import Foundation
import BrimCore

/// Asks Anthropic for the current usage, using the login Claude Code already stored.
///
/// That login is the only credential that can read this endpoint. A token from
/// `claude setup-token` carries the `user:inference` scope alone, and
/// `/api/oauth/usage` requires `user:profile`, so Anthropic answers 401 to every one.
/// Claude Code gates its own usage fetch on the same scope.
///
/// This is what makes Claude's numbers live. The local cache Claude Code writes is
/// only refreshed occasionally, measured at over two weeks stale on a machine in
/// daily use, so it cannot be the primary source. This can be polled on our own
/// schedule.
///
/// The credential is used read-only and sent only to the host that issued it. When it
/// has lapsed the app says so and keeps showing the cached reading with its true age,
/// rather than refreshing the token itself and risking signing the user out of Claude
/// Code.
@MainActor
final class ClaudeLiveConnection {
    var onSnapshot: ((UsageSnapshot) -> Void)?
    var onUnavailable: ((Unavailable) -> Void)?

    enum Unavailable: Equatable, Error {
        case noCredential
        case credentialExpired
        case accessDenied(OSStatus)
        case rejected
        case network(String)
        case unreadable

        var message: String {
            switch self {
            case .noCredential:
                "No Claude Code login was found on this Mac. One allowance covers Claude chat, "
                    + "Claude Code and Claude Design, but the only credential on a Mac that can read "
                    + "it belongs to Claude Code, the command line tool — the Claude app and claude.ai "
                    + "leave none behind. Install Claude Code and sign in once and these numbers turn "
                    + "on by themselves, including your chat usage. You never have to use it."
            case .credentialExpired:
                "Claude Code’s saved login has lapsed. Only Claude Code can renew it, and running "
                    + "the `claude` command once does: Brim sees the new login and goes live again "
                    + "by itself, within seconds."
            case .rejected:
                "Anthropic rejected Claude Code’s saved login. Signing in again with Claude Code "
                    + "replaces it."
            case .accessDenied(let status):
                "Brim wasn’t allowed to read Claude Code’s saved login, so it can’t fetch live "
                    + "usage: \(ClaudeCredential.explain(status))"
            case .network(let detail):
                "Couldn’t reach Anthropic for live usage: \(detail)"
            case .unreadable:
                "Anthropic returned usage in a form this version doesn’t understand."
            }
        }
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private var task: Task<Void, Never>?
    private var generation = UUID()

    /// The credential, kept so the refresh timer does not re-read the Keychain on
    /// every cycle.
    ///
    /// Reading another app's Keychain item asks macOS for permission, and on the
    /// refresh cadence that became a password prompt every minute. Reading it once and
    /// reusing it until it expires turns that flood into, at most, one prompt when the
    /// credential is first read and one more when it lapses.
    private var cached: ClaudeCredential.Token?
    /// One lookup at a time. The refresh cadence and a click can otherwise queue
    /// several, and each one is its own chance of a Keychain prompt.
    private var isLookingUp = false

    func refresh() {
        if let cached, cached.isValid() {
            fetch(cached)
            return
        }
        // Off the main thread, always. Reading a Keychain item is a synchronous call
        // into securityd that can take a moment on its own, and when macOS decides to
        // ask permission for it, it does not return until the user answers the dialog.
        // On the main actor that is the whole interface frozen, which is what a click
        // on a ring used to buy: the refresh it asked for arrived only after the app
        // had stopped responding for as long as the Keychain took.
        guard !isLookingUp else { return }
        isLookingUp = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let lookup = ClaudeCredential.look()
            await MainActor.run { [weak self] in self?.apply(lookup) }
        }
    }

    private func apply(_ lookup: ClaudeCredential.Lookup) {
        isLookingUp = false
        switch lookup {
        case .missing: deliver(.noCredential)
        case .denied(let status): deliver(.accessDenied(status))
        case .expired: cached = nil; deliver(.credentialExpired)
        case .found(let token):
            cached = token
            fetch(token)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        generation = UUID()
        cached = nil
    }

    private func fetch(_ token: ClaudeCredential.Token) {
        task?.cancel()
        let generation = UUID()
        self.generation = generation

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Brim", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        task = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                // A reply from a superseded request must never overwrite a newer one.
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.handle(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                            longLived: token.isLongLived)
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.deliver(.network(error.localizedDescription))
            }
        }
    }

    private func handle(data: Data, status: Int, longLived: Bool) {
        // A rejected long-lived token needs replacing; an expired short one only
        // needs waiting out, so they must not share a message.
        guard status != 401 else {
            // A credential the server has now rejected must be re-read next time,
            // not reused, or the app would keep sending a dead one.
            cached = nil
            return deliver(longLived ? .rejected : .credentialExpired)
        }
        guard (200..<300).contains(status) else {
            return deliver(.network("the server replied \(status)."))
        }
        do {
            var snapshot = try UsageParser.claude(data)
            snapshot.source = .claudeLive
            onSnapshot?(snapshot)
        } catch {
            deliver(.unreadable)
        }
    }

    private func deliver(_ reason: Unavailable) {
        onUnavailable?(reason)
    }
}
