import Foundation

/// One reading of Claude's usage, plus who it belongs to.
public struct ClaudeAccountUsage: Equatable, Sendable {
    public var snapshot: UsageSnapshot
    public var accountUUID: String?
    public init(snapshot: UsageSnapshot, accountUUID: String?) {
        self.snapshot = snapshot
        self.accountUUID = accountUUID
    }
}

/// Reads the usage block Claude Code keeps in `~/.claude.json`.
///
/// **This is a cache, not a feed.** Claude Code rewrites the surrounding file
/// constantly but refreshes `cachedUsageUtilization` only occasionally, so a reading
/// here can be days old. `fetchedAtMs` is carried through as the snapshot's
/// `updatedAt` precisely so the age is visible rather than implied. Never present
/// one of these as current without showing when it was taken.
///
/// The block's own shape is read by `ClaudeUsageFormat`, which the live endpoint
/// shares. The two used to be parsed separately, and the live one was parsing a format
/// Anthropic does not return.
public enum ClaudeUsageCache {
    /// Parses the whole `~/.claude.json` document. Returns nil when it carries no
    /// usage block at all, which is different from carrying an empty one. An empty
    /// block deliberately clears previous quotas.
    public static func read(_ data: Data) throws -> ClaudeAccountUsage? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParseError.invalidData
        }
        guard let cache = root["cachedUsageUtilization"] as? [String: Any] else { return nil }
        guard let fetchedMs = UsageParser.number(cache["fetchedAtMs"]), fetchedMs > 0 else {
            throw UsageParseError.invalidData
        }
        let fetchedAt = Date(timeIntervalSince1970: fetchedMs / 1000)
        let utilization = cache["utilization"] as? [String: Any] ?? [:]

        let windows = ClaudeUsageFormat.windows(in: utilization)

        let snapshot = UsageSnapshot(provider: .claudeCode, windows: windows,
                                     source: .claudeCache, updatedAt: fetchedAt)
        return ClaudeAccountUsage(snapshot: snapshot, accountUUID: cache["accountUuid"] as? String)
    }

    /// Kept as the name other readers already call. The parsing itself lives in
    /// `ClaudeUsageFormat`, which the live path shares.
    public static func date(_ value: Any?) -> Date? { ClaudeUsageFormat.date(value) }
}
