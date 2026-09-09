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
///
/// **There is no separate figure for Claude chat, and none for Claude Design.** One
/// allowance is metered across all of Anthropic's surfaces, and `five_hour` and
/// `seven_day` are it. What the format does carry is a `scope.surface` on each limit,
/// and a row of per-surface siblings, and both are read here so that a breakdown
/// appears by itself on the day Anthropic starts filling them in. On every account
/// seen so far they are null.
public enum ClaudeUsageFormat {
    /// Every limit in a usage block, richest form first.
    public static func windows(in utilization: [String: Any]) -> [UsageWindow] {
        let limits = (utilization["limits"] as? [[String: Any]]).map(limitWindows) ?? []
        let base = limits.isEmpty ? namedWindows(utilization) : limits
        // Appended rather than merged: these are separate allowances when they are
        // reported at all, and `limits` has never yet carried them.
        let taken = Set(base.map(\.id))
        return base + surfaceWindows(utilization).filter { !taken.contains($0.id) }
    }

    private static func limitWindows(_ limits: [[String: Any]]) -> [UsageWindow] {
        limits.compactMap { entry in
            // A missing percentage is unknown, not zero, so the entry is dropped.
            guard let percent = UsageParser.number(entry["percent"]), percent >= 0 else { return nil }
            let kind = entry["kind"] as? String ?? "limit"
            let group = entry["group"] as? String
            let scope = entry["scope"] as? [String: Any]
            let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
            let surface = name(of: scope?["surface"])
            // A limit scoped to a model, a surface, or both. Joined in one label so a
            // future "Fable on Claude Design" reads as the one window it is.
            let label = [model, surface].compactMap { $0 }.joined(separator: " · ")
            let scopeLabel = label.isEmpty ? nil : label
            return UsageWindow(id: ([kind] + [model, surface].compactMap { $0 }).joined(separator: ":"),
                               title: title(kind: kind, scope: scopeLabel),
                               usedPercent: percent,
                               resetsAt: date(entry["resets_at"]),
                               durationMinutes: duration(group: group, kind: kind),
                               severity: UsageSeverity(reported: entry["severity"] as? String),
                               scopeLabel: scopeLabel,
                               isActive: entry["is_active"] as? Bool ?? false)
        }
    }

    /// A surface is a string in some payloads and an object in others, so both are
    /// accepted rather than guessing which one Anthropic settles on.
    private static func name(of value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        guard let object = value as? [String: Any] else { return nil }
        for key in ["display_name", "name", "id"] {
            if let text = object[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    private static func title(kind: String, scope: String?) -> String {
        switch kind {
        case "session": scope.map { "\($0) · session" } ?? "Current session"
        case "weekly_all": scope.map { "\($0) · weekly" } ?? "All models · weekly"
        case "weekly_scoped": scope.map { "\($0) · weekly" } ?? "Scoped · weekly"
        default: scope.map { "\($0) · \(readable(kind))" } ?? readable(kind)
        }
    }

    private static func readable(_ kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func duration(group: String?, kind: String) -> Int? {
        switch group ?? kind {
        case "session": 300
        case "weekly": 10080
        default: nil
        }
    }

    /// Per-surface weekly siblings, for the surfaces that can be named honestly.
    ///
    /// The block also carries buckets under internal code names — `nimbus_quill`,
    /// `tangelo`, `iguana_necktie` and others — which are deliberately not read. They
    /// arrive without any label saying what they meter, and a ring called "Nimbus
    /// Quill" tells nobody anything; one of them reports 0 on a normal account, so
    /// showing every non-null bucket would put exactly that on screen. A bucket is
    /// listed here only once it can be given a name that is true.
    private static let surfaces: [(key: String, title: String)] = [
        ("seven_day_opus", "Opus · weekly"),
        ("seven_day_sonnet", "Sonnet · weekly"),
        ("seven_day_cowork", "Cowork · weekly"),
        ("seven_day_oauth_apps", "Connected apps · weekly")
    ]

    private static func surfaceWindows(_ utilization: [String: Any]) -> [UsageWindow] {
        surfaces.compactMap { key, title in
            // Null is the normal state of every one of these. Absent means the surface
            // is not metered separately for this account, which is not the same as zero.
            guard let entry = utilization[key] as? [String: Any],
                  let percent = UsageParser.number(entry["utilization"]), percent >= 0 else { return nil }
            return UsageWindow(id: key, title: title, usedPercent: percent,
                               resetsAt: date(entry["resets_at"]), durationMinutes: 10080,
                               scopeLabel: title.replacingOccurrences(of: " · weekly", with: ""))
        }
    }

    /// Used when `limits` is absent. The siblings `seven_day_opus` and
    /// `seven_day_sonnet` are null on real accounts and are read by `surfaceWindows`.
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
