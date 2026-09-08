import Foundation
import Security

/// Removes any long-lived Claude token earlier builds stored.
///
/// Those builds asked people to run `claude setup-token` and kept what it printed. That
/// was a dead end: a setup-token credential carries the `user:inference` scope alone,
/// and `/api/oauth/usage` requires `user:profile`, so Anthropic rejected every one of
/// them with a 401. Claude Code's own binary gates its usage fetch on exactly that
/// scope, and says so plainly: "env-var and setup-token sessions default to
/// user:inference only".
///
/// So the app no longer mints, asks for, or keeps a token of its own. Live usage comes
/// from the login Claude Code already holds, which does carry the scope. Anything left
/// behind under the old Keychain names is deleted on launch: it can only ever produce a
/// 401, and a credential that cannot work should not sit in someone's Keychain.
enum ClaudeTokenStore {
    private static let services = ["com.michaelhanna.brim.claude-token",
                                   "com.usagenotch.app.claude-token"]
    private static let account = "claude"

    /// Deletes the stored token, if any. Returns true when one was there to remove,
    /// so a build that inherits one can say why live usage just started working.
    @discardableResult
    static func removeLegacyToken() -> Bool {
        var removed = false
        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            if SecItemDelete(query as CFDictionary) == errSecSuccess { removed = true }
        }
        return removed
    }
}
