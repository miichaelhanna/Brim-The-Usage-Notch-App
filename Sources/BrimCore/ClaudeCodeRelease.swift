import Foundation

/// Where Anthropic publishes Claude Code, and how to tell a real build from anything
/// else, for Brim's Sign In to install it.
///
/// This is what Anthropic's own installer script does, done here instead of by running
/// that script: Brim does not run shell, so it fetches the same files from the same
/// place and checks them the same way. The build's SHA-256 has to match Anthropic's
/// manifest, and then its signature has to be Anthropic's, before it is run at all.
public enum ClaudeCodeRelease {
    public static let base = URL(string: "https://downloads.claude.ai/claude-code-releases")!
    /// Anthropic PBC's Developer ID team, which signs every macOS build.
    public static let signingTeam = "Q6L2SF6YDW"

    public static var latest: URL { base.appendingPathComponent("latest") }

    public static func manifest(_ version: String) -> URL {
        base.appendingPathComponent(version).appendingPathComponent("manifest.json")
    }

    public static func binary(_ version: String, platform: String) -> URL {
        base.appendingPathComponent(version).appendingPathComponent(platform).appendingPathComponent("claude")
    }

    /// The Mac's own platform name. An Intel build of Brim running under Rosetta is on
    /// an Apple silicon Mac, and gets the native build, as the installer script does.
    public static func platform(arm64: Bool, translated: Bool) -> String {
        arm64 || translated ? "darwin-arm64" : "darwin-x64"
    }

    /// The version `latest` names, or nil for anything that is not one. An error page
    /// served with a 200 must not become part of a download URL.
    public static func version(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              text.count < 64,
              text.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9.+-]*$"#, options: .regularExpression) != nil
        else { return nil }
        return text
    }

    /// The SHA-256 the manifest promises for this platform's build, lowercased.
    public static func checksum(_ manifest: Data, platform: String) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let platforms = root["platforms"] as? [String: Any],
              let entry = platforms[platform] as? [String: Any],
              let checksum = (entry["checksum"] as? String)?.lowercased(),
              checksum.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        else { return nil }
        return checksum
    }
}
