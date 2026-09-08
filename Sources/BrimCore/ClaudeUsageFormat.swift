import Foundation

/// The shape Anthropic reports Claude usage in.
///
/// The same structure arrives from two places: live from `/api/oauth/usage`, and from
/// the `cachedUsageUtilization` block Claude Code writes into `~/.claude.json`. Live it
/// sits at the top level of the response; cached it sits under `utilization`. Only the
/// wrapper differs, so only the wrapper is handled separately.
///
/// It was not always shared, and that cost the app its live readings: the cache was
/// parsed from `utilization.limits`, while the live path looked for a `rate_limits`
/// object with `used_percentage` and epoch timestamps. No such object is returned, so
/// every live fetch parsed to zero windows, answered 200, and quietly showed nothing.
/// One reader for one format is the fix, and the reason it stays one reader.
///
/// `limits` is preferred over the sibling named keys. It is the richer structure: it
/// carries the provider's own severity, marks which window is actually doing the
/// limiting, and reports model-scoped limits that the named keys leave null.
public enum ClaudeUsageFormat {
    /// Every limit in a usage block, richest form first.
    public static func windows(in utilization: [String: Any]) -> [UsageWindow] {
        let limits = (utilization["limits"] as? [[String: Any]]).map(limitWindows) ?? []
        return limits.isEmpty ? namedWindows(utilization) : limits
    }

    private static func limitWindows(_ limits: [[String: Any]]) -> [UsageWindow] {
        limits.compactMap { entry in
            // A missing percentage is unknown, not zero, so the entry is dropped.
            guard let percent = UsageParser.number(entry["percent"]), percent >= 0 else { return nil }
            let kind = entry["kind"] as? String ?? "limit"
            let group = entry["group"] as? String
            let model = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
            return UsageWindow(id: [kind, model].compactMap { $0 }.joined(separator: ":"),
                               title: title(kind: kind, model: model),
                               usedPercent: percent,
                               resetsAt: date(entry["resets_at"]),
                               durationMinutes: duration(group: group, kind: kind),
                               severity: UsageSeverity(reported: entry["severity"] as? String),
                               scopeLabel: model,
                               isActive: entry["is_active"] as? Bool ?? false)
        }
    }

    private static func title(kind: String, model: String?) -> String {
        switch kind {
        case "session": "Current session"
        case "weekly_all": "All models · weekly"
        case "weekly_scoped": model.map { "\($0) · weekly" } ?? "Scoped · weekly"
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func duration(group: String?, kind: String) -> Int? {
        switch group ?? kind {
        case "session": 300
        case "weekly": 10080
        default: nil
        }
    }

    /// Used when `limits` is absent. The siblings `seven_day_opus` and
    /// `seven_day_sonnet` are null on real accounts and are deliberately not read.
    private static func namedWindows(_ utilization: [String: Any]) -> [UsageWindow] {
        let definitions = [("five_hour", "Current session", 300), ("seven_day", "All models · weekly", 10080)]
        return definitions.compactMap { key, title, minutes in
            guard let entry = utilization[key] as? [String: Any],
                  let percent = UsageParser.number(entry["utilization"]), percent >= 0 else { return nil }
            return UsageWindow(id: key, title: title, usedPercent: percent,
                               resetsAt: date(entry["resets_at"]), durationMinutes: minutes)
        }
    }

    /// ISO 8601 with or without fractional seconds, or epoch seconds. Both appear:
    /// the status line that used to feed this app sent epoch numbers, and everything
    /// Anthropic returns now is a string.
    public static func date(_ value: Any?) -> Date? {
        if let seconds = UsageParser.number(value) { return Date(timeIntervalSince1970: seconds) }
        guard let text = value as? String, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
