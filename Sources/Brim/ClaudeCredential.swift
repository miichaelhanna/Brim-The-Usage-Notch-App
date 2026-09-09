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
    /// Phase two reads the most recently written matching items, newest first, and
    /// stops at the first one it actually reads. Claude Code keeps a base entry plus
    /// per-install siblings, and prompting once per entry would mean a wall of dialogs,
    /// so the search moves on in exactly one case: a read that macOS refused on its own,
    /// which showed no dialog and so cost the person nothing. Any read that succeeded
    /// ends the walk, and so does an explicit cancel, because that is someone saying no.
    ///
    /// It reads more than one because reading exactly one used to end the whole search
    /// on a single silent refusal, with a working sibling directly behind it and
    /// nothing on screen to say a read had even been attempted.
    /// Claude Code's login, from wherever this Mac happens to keep it.
    ///
    /// The Keychain is the usual place and is tried first. It is not the only one:
    /// Claude Code falls back to a plain file at `~/.claude/.credentials.json` when it
    /// cannot use the Keychain, and an install that took that path leaves nothing in
    /// the Keychain at all. Looking only there reported "no Claude Code login on this
    /// Mac" to someone signed into Claude Code, and — because there was no secret to
    /// ask about — macOS never offered the permission dialog either, so the app looked
    /// broken rather than mistaken.
    static func look(now: Date = Date(), maximumReads: Int = 4) -> Lookup {
        let keychain = lookInKeychain(now: now, maximumReads: maximumReads)
        if case .found = keychain { return keychain }
        guard let token = fileToken() else { return keychain }
        if token.isValid(at: now) { return .found(token) }
        // A stale file is still better evidence than a Keychain that held nothing:
        // it says a login exists and has lapsed, which is a different thing to fix.
        if case .missing = keychain, let expiry = token.expiresAt { return .expired(at: expiry) }
        return keychain
    }

    /// The file Claude Code writes when it is not using the Keychain. Read-only, and
    /// only ever this one path.
    static var credentialsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    static func fileToken() -> Token? {
        guard let data = try? Data(contentsOf: credentialsFile) else { return nil }
        return parse(data)
    }

    private static func lookInKeychain(now: Date, maximumReads: Int) -> Lookup {
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
                // A read that succeeded means macOS is showing dialogs and they are
                // being answered, so every further sibling costs another one. Stop:
                // the siblings are older installs and older still means more likely
                // lapsed, and a lapsed newest entry is fixed by Claude Code renewing
                // it rather than by hunting behind it.
                break
            } else if read != errSecItemNotFound {
                refusal = read
                // Answering a dialog is the one refusal worth honouring immediately.
                // Every other status was decided without asking, so the next sibling
                // costs the person nothing.
                if read == errSecUserCanceled { break }
            }
        }

        if let latest = tokens.compactMap(\.expiresAt).max() { return .expired(at: latest) }
        if let refusal { return .denied(refusal) }
        return .missing
    }

    /// When Claude Code last wrote a login, without reading one.
    ///
    /// Attributes only, exactly like the first phase of `look`: no secret is touched,
    /// so this needs no permission and raises no prompt. That is what lets it run on a
    /// timer while a lapsed login is on screen, which reading the token could not.
    static func lastChanged() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let items = found as? [[String: Any]] else { return nil }
        return items
            .filter { ($0[kSecAttrService as String] as? String)?.hasPrefix(servicePrefix) ?? false }
            .compactMap { $0[kSecAttrModificationDate as String] as? Date }
            .max()
    }

    /// What a refusal actually was, in words.
    ///
    /// These do not describe one situation. A remembered Deny and a keychain macOS
    /// will not open a dialog for both end in no prompt and no usage, and the person
    /// in front of them can only act on one of them, so the app has to tell them apart.
    static func explain(_ status: OSStatus) -> String {
        switch status {
        case errSecUserCanceled, errSecAuthFailed:
            return "the permission was declined once and macOS remembers that answer, so it no "
                + "longer asks. Open Keychain Access, find “Claude Code-credentials”, and allow Brim "
                + "on its Access Control tab."
        case errSecInteractionNotAllowed:
            return "macOS would not open the permission dialog. That usually means the login "
                + "keychain is locked; unlocking it in Keychain Access and trying again is the fix."
        case errSecMissingEntitlement:
            return "macOS placed that login somewhere only Claude Code itself can reach, so no "
                + "permission dialog can be offered for it."
        case errSecItemNotFound:
            return "the login was gone by the time it was read."
        default:
            return "macOS refused the read and gave no reason beyond code \(status)."
        }
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
