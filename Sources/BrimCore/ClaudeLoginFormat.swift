import Foundation

/// Reads the login Claude Code saves, in whatever shape this Mac's copy wrote it.
///
/// Claude Code's own format is `{"claudeAiOauth": {"accessToken", "expiresAt", …}}`,
/// with `expiresAt` in milliseconds. The parser once accepted exactly that and nothing
/// else, so a login written any other way — an expiry that was absent, in seconds, or
/// a string; the JSON stored as hex — was indistinguishable from no login at all, and
/// was reported as macOS refusing a read that had in fact succeeded.
///
/// Everything here is tolerance about *where* and *how* the same facts are written.
/// Nothing is guessed: without an access token there is no login, and an expiry that
/// cannot be read is left unknown, so the server's reply decides whether it is valid.
public enum ClaudeLoginFormat {
    public struct Login: Equatable {
        public let accessToken: String
        public let expiresAt: Date?
        public let subscription: String?
    }

    public static func parse(_ data: Data) -> Login? {
        guard let root = object(from: data) else { return nil }
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        guard let token = oauth["accessToken"] as? String ?? oauth["access_token"] as? String,
              !token.isEmpty else { return nil }
        return Login(accessToken: token,
                     expiresAt: expiry(oauth["expiresAt"] ?? oauth["expires_at"]),
                     subscription: oauth["subscriptionType"] as? String)
    }

    /// The JSON, whether it was stored as itself or as the hex of itself. The
    /// `security` tool writes and prints non-text payloads as hex, and an install that
    /// saved its login through it can leave exactly that behind.
    static func object(from data: Data) -> [String: Any]? {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return root }
        guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let decoded = hex(text) else { return nil }
        return try? JSONSerialization.jsonObject(with: decoded) as? [String: Any]
    }

    static func hex(_ text: String) -> Data? {
        let digits = Array(text.utf8)
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
        }
        return Data(bytes)
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    /// Milliseconds, seconds, or an ISO 8601 string. Any number past 10¹¹ is
    /// milliseconds: as seconds it would be the year 5138.
    static func expiry(_ value: Any?) -> Date? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            let raw = number.doubleValue
            guard raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw > 1e11 ? raw / 1000 : raw)
        case let text as String:
            if let number = Double(text) { return expiry(NSNumber(value: number)) }
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter.date(from: text)
        default:
            return nil
        }
    }

    /// The login's shape, by key and kind of value, with no value ever printed — not
    /// even short ones, since every string in this object is part of a credential.
    /// This is what `--diagnose-claude` shows when a login was read but not understood,
    /// so the next format can be supported from a report that is safe to paste.
    public static func outline(_ data: Data) -> [String] {
        guard let root = object(from: data) else {
            let text = String(data: data, encoding: .utf8) != nil ? "text" : "binary"
            return ["  (not JSON: \(data.count) bytes of \(text))"]
        }
        return outline(root, path: "")
    }

    private static func outline(_ value: Any, path: String) -> [String] {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().flatMap { key in
                outline(dictionary[key]!, path: path.isEmpty ? key : "\(path).\(key)")
            }
        case let array as [Any]: return ["  \(path): array of \(array.count)"]
        case is NSNull: return ["  \(path): null"]
        case let number as NSNumber:
            return ["  \(path): \(CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number")"]
        case is String: return ["  \(path): string"]
        default: return ["  \(path): ?"]
        }
    }
}
