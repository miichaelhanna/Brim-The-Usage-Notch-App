import Foundation

/// Removes the terminal status-line bridge that earlier versions installed.
///
/// That bridge wrapped `statusLine` in `~/.claude/settings.json` so Claude Code piped
/// its status payload into a signed helper binary. Usage now comes from Claude's own
/// cache, so the wrapper is dead weight, and leaving it behind would keep mutating a
/// file this app no longer has any business touching.
///
/// The previous uninstall was incomplete: it restored the status line but left the
/// helper, the backup and the support directory in place, and gave up entirely if the
/// user had since hand-edited their settings. This does the whole job, and is safe to
/// run on every launch.
enum LegacyBridgeCleanup {
    private static var settings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    /// Where the bridge kept its files. The app was called Usage Notch then, and this
    /// has to keep pointing at that folder rather than follow `AppPaths` to the new one:
    /// the whole point is finding what an older install left behind.
    private static var legacySupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/UsageNotch", isDirectory: true)
    }
    private static var backup: URL { legacySupport.appendingPathComponent("original-statusline.json") }
    private static var helper: URL { legacySupport.appendingPathComponent("usage-notch-bridge") }
    private static var snapshot: URL { legacySupport.appendingPathComponent("claude-usage.json") }

    /// What was found and undone, for the connection UI to report once.
    struct Result: Equatable {
        var restoredStatusLine = false
        var removedHelper = false
        var leftForeignStatusLine = false
    }

    @discardableResult
    static func run() -> Result {
        var result = Result()
        let manager = FileManager.default

        if let command = configuredCommand() {
            if isOurs(command) {
                result.restoredStatusLine = restoreStatusLine()
            } else {
                // The user replaced the command themselves at some point. Their line
                // is theirs; only our own leftovers get cleaned up.
                result.leftForeignStatusLine = command.contains("usage_notch")
            }
        }

        for file in [helper, backup, snapshot] where manager.fileExists(atPath: file.path) {
            if (try? manager.removeItem(at: file)) != nil { result.removedHelper = true }
        }

        // The old folder goes once it is empty. Anything else still in it, readings an
        // older build saved, say, is left for the person to look at.
        if let contents = try? manager.contentsOfDirectory(atPath: legacySupport.path), contents.isEmpty {
            try? manager.removeItem(at: legacySupport)
        }
        return result
    }

    private static func configuredCommand() -> String? {
        guard let data = try? Data(contentsOf: settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let line = root["statusLine"] as? [String: Any] else { return nil }
        return line["command"] as? String
    }

    /// Matches the marker the bridge always wrote, so a status line we never touched
    /// is never rewritten.
    private static func isOurs(_ command: String) -> Bool {
        command.contains("--capture-claude") && command.contains("usage_notch_bridge_version")
    }

    private static func restoreStatusLine() -> Bool {
        guard var root = try? JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] else {
            return false
        }
        // The bridge chained the user's original command after its own. Restore it
        // when the backup is readable; otherwise drop the key rather than leave a
        // command pointing at a helper that no longer exists.
        if let data = try? Data(contentsOf: backup),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let original = saved["statusLine"], !(original is NSNull) {
            root["statusLine"] = original
        } else {
            root.removeValue(forKey: "statusLine")
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: root,
                                                        options: [.prettyPrinted, .sortedKeys]) else { return false }
        return (try? encoded.write(to: settings, options: .atomic)) != nil
    }
}
