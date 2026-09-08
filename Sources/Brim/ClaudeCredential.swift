import Foundation
import Security

/// Finds the credential that can read this account's Claude usage.
///
/// There is exactly one: **Claude Code's own saved login**, read-only.
///
/// Earlier builds preferred a token from `claude setup-token`, on the reasoning that a
/// separate long-lived credential is safer than borrowing this one. The reasoning was
/// sound and the premise was wrong: a setup-token credential carries `user:inference`
/// alone, and `/api/oauth/usage` requires `user:profile`, so Anthropic rejected every
/// one with a 401. Claude Code gates its own usage fetch on that same scope. A sign-in
/// credential has it; a minted token cannot.
///
/// Nothing here ever writes, refreshes or rotates Claude Code's credential. Two
/// processes writing a rotating refresh token is how people get silently signed out,
/// and that failure would read as "this app broke my Claude".
///
/// A token is sent to exactly one place, `api.anthropic.com`, which issued it.
enum ClaudeCredential {
    /// Claude Code keeps a base entry plus per-install siblings, so the newest valid
    /// one wins rather than assuming a single fixed name.
    static let servicePrefix = "Claude Code-credentials"

    struct Token: Equatable {
        let value: String
        /// Nil for a long-lived token, whose expiry this app does not track. The
        /// server's reply decides validity rather than a local clock.
        let expiresAt: Date?
        let subscription: String?
        let isLongLived: Bool
        func isValid(at now: Date = Date()) -> Bool { expiresAt.map { $0 > now } ?? true }
    }

    enum Lookup: Equatable {
        case found(Token)
        /// A login exists but has lapsed; Claude Code renews it when next used.
        case expired(at: Date)
        case missing
        /// The user declined the Keychain prompt, or macOS refused.
        case denied(OSStatus)
    }

    /// Reading is done in two phases, which matters for both permission and manners.
    ///
    /// Phase one asks for item *names* only. An attributes-only query does not touch
    /// any secret, so it needs no permission and raises no prompt. Asking for every
    /// stored password's contents at once, by contrast, is refused outright, and
    /// deserves to be.
    ///
    /// Phase two reads only the few most recently written matching items. Claude Code
    /// keeps a base entry plus per-install siblings, and prompting once per entry
    /// would mean a wall of dialogs; the newest is the one it is actually using.
    static func look(now: Date = Date(), maximumReads: Int = 1) -> Lookup {
        let discovery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(discovery as CFDictionary, &found)
        guard status == errSecSuccess, let items = found as? [[String: Any]] else {
            return status == errSecItemNotFound ? .missing : .denied(status)
        }

        let matches = items
            .filter { ($0[kSecAttrService as String] as? String)?.hasPrefix(servicePrefix) ?? false }
            .sorted { left, right in
                let l = left[kSecAttrModificationDate as String] as? Date ?? .distantPast
                let r = right[kSecAttrModificationDate as String] as? Date ?? .distantPast
                return l > r
            }
        guard !matches.isEmpty else { return .missing }

        var tokens: [Token] = []
        var refusal: OSStatus?
        for item in matches.prefix(maximumReads) {
            guard let service = item[kSecAttrService as String] as? String else { continue }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true
            ]
            var value: CFTypeRef?
            let read = SecItemCopyMatching(query as CFDictionary, &value)
            if read == errSecSuccess, let data = value as? Data, let token = parse(data) {
                // The newest valid one is enough; stop before prompting again.
                if token.isValid(at: now) { return .found(token) }
                tokens.append(token)
            } else if read != errSecItemNotFound {
                refusal = read
            }
        }

        if let latest = tokens.compactMap(\.expiresAt).max() { return .expired(at: latest) }
        if let refusal { return .denied(refusal) }
        return .missing
    }

    static func parse(_ data: Data) -> Token? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        guard let value = oauth["accessToken"] as? String, !value.isEmpty,
              let milliseconds = oauth["expiresAt"] as? Double, milliseconds > 0 else { return nil }
        return Token(value: value,
                     expiresAt: Date(timeIntervalSince1970: milliseconds / 1000),
                     subscription: oauth["subscriptionType"] as? String,
                     isLongLived: false)
    }
}
