import Foundation
import BrimCore

/// `--diagnose-claude`: prints what the app can read from Claude Code's usage cache.
///
/// Reads a local file and prints quota percentages only. It starts no session, sends
/// nothing, and touches no credential.
enum ClaudeUsageDiagnostic {
    static func run() {
        let path = AppPaths.claudeConfig
        print("Source: \(path.path)")
        guard let data = try? Data(contentsOf: path) else {
            print("Not readable. Claude Code may not be installed for this user.")
            return
        }
        do {
            guard let reading = try ClaudeUsageCache.read(data) else {
                print("Present, but carries no cachedUsageUtilization block yet.")
                print("Run /usage in a Claude Code session to create one.")
                return
            }
            let age = Date().timeIntervalSince(reading.snapshot.updatedAt)
            print("Account: \(reading.accountUUID ?? "unknown")")
            print("Reading taken: \(reading.snapshot.updatedAt.formatted(.iso8601)) "
                  + "(\(String(format: "%.1f", age / 3600))h ago)")
            if reading.snapshot.isStale() { print("STALE. Claude Code has not refreshed this recently.") }
            guard !reading.snapshot.windows.isEmpty else {
                print("No limits reported for this account.")
                return
            }
            print("Windows (* = the one currently limiting):")
            for window in reading.snapshot.windows {
                let reset = window.resetsAt.map { "resets \($0.formatted(.iso8601))" } ?? "no reset time"
                print("  \(window.isActive ? "*" : " ") \(window.title): "
                      + "\(Int(window.usedPercent.rounded()))% [\(window.severity.rawValue)] \(reset)")
            }
        } catch {
            print("Could not parse: \(error.localizedDescription)")
        }
        checkLive()
    }

    /// Reports whether live usage is reachable. macOS asks the user before letting
    /// this read Claude Code's saved login; declining simply means no live usage.
    private static func checkLive() {
        print("")
        print("Live source: api.anthropic.com/api/oauth/usage")
        // Which of the two places Claude Code might keep its login actually holds one.
        // A machine with neither, and a machine whose login is in the file rather than
        // the Keychain, produce the same silence otherwise.
        let file = ClaudeCredential.credentialsFile
        print("Credentials file \(file.path): "
              + (FileManager.default.fileExists(atPath: file.path)
                 ? (ClaudeCredential.fileToken() == nil ? "present, unreadable" : "present, readable") : "absent"))
        switch ClaudeCredential.look() {
        case .missing:
            print("No Claude Code login found, in the Keychain or the credentials file.")
        case .denied(let status):
            print("Keychain access was refused (OSStatus \(status)), so live usage is unavailable.")
            print("Meaning: \(ClaudeCredential.explain(status))")
            print("A dev build has no stable code identity; a signed build is granted access once.")
        case .expired(let when):
            print("Saved login expired \(when.formatted(.iso8601)). Claude Code renews it on next use.")
        case .found(let token):
            let expiry = token.expiresAt?.formatted(.iso8601) ?? "unknown"
            print("Using Claude Code's own saved login, expires \(expiry), "
                  + "plan \(token.subscription ?? "unknown").")
            print("This endpoint needs the user:profile scope, which a sign-in has and a")
            print("`claude setup-token` token does not. A 401 below means this login was refused.")
            fetch(token)
        }
    }

    private static func fetch(_ token: ClaudeCredential.Token) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                                 timeoutInterval: 20)
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Brim", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { print("Request failed: \(error.localizedDescription)"); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("HTTP \(status)")
            guard let data else { return }
            guard (200..<300).contains(status) else {
                print(String(data: data.prefix(300), encoding: .utf8) ?? "")
                return
            }
            do {
                let snapshot = try UsageParser.claude(data)
                print("LIVE READING, \(snapshot.windows.count) window(s):")
                // A 200 that parses to nothing means the response shape moved. Say what
                // arrived, by keys and value kinds, enough to fix a parser, and safe to
                // paste into an issue because no value is printed.
                if snapshot.windows.isEmpty, let root = try? JSONSerialization.jsonObject(with: data) {
                    print("Nothing was parsed from a successful reply. What arrived:")
                    print(Self.outline(root).joined(separator: "\n"))
                }
                for window in snapshot.windows {
                    print("   \(window.title): \(Int(window.usedPercent.rounded()))%")
                }
            } catch {
                print("Could not parse the live reply: \(error.localizedDescription)")
            }
        }.resume()
        _ = semaphore.wait(timeout: .now() + 25)
    }

    /// Describes JSON by its keys and value kinds, never its values. A parser that
    /// silently reads nothing from a 200 is otherwise invisible.
    static func outline(_ value: Any, path: String = "", depth: Int = 0) -> [String] {
        guard depth < 5 else { return ["  \(path): …"] }
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().flatMap { key -> [String] in
                outline(dictionary[key]!, path: path.isEmpty ? key : "\(path).\(key)", depth: depth + 1)
            }
        case let array as [Any]:
            guard !array.isEmpty else { return ["  \(path): [] (empty)"] }
            return ["  \(path): [\(array.count)]"] + array.prefix(8).enumerated().flatMap {
                outline($0.element, path: "\(path)[\($0.offset)]", depth: depth + 1)
            }
        case is NSNull: return ["  \(path): null"]
        case let number as NSNumber:
            return ["  \(path): \(CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number")"]
        case let text as String:
            // Short identifiers are the ones a parser switches on, so they are shown.
            return ["  \(path): string\(text.count <= 24 ? " = \"\(text)\"" : "")"]
        default: return ["  \(path): ?"]
        }
    }

}
