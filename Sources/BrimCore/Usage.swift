import Foundation

/// A source this app knows how to read.
///
/// Four sources, two allowances: Claude and Claude Code draw on one subscription, and
/// ChatGPT and Codex on one Work allowance. Readings are still tracked per source,
/// because they arrive from different places and a reading has to say where it came from,
/// but each pair is shown once, under `displayProvider`.
public enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude, chatgpt, codex, claudeCode
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }
    /// The provider whose ring stands for this one. A pair sharing an allowance would
    /// otherwise show the same number twice, and two rings that always agree are one
    /// ring with a confusing label.
    public var displayProvider: Provider {
        switch self {
        case .claudeCode: .claude
        case .codex: .chatgpt
        case .claude, .chatgpt: self
        }
    }
    public var isDisplayed: Bool { displayProvider == self }
    /// What the ring is called. Kept as its own property so the name the interface
    /// shows can differ from the raw source name if it ever has to.
    public var usageName: String { name }
    /// What this figure covers, and what it does not.
    public var usageScopeNote: String? {
        switch displayProvider {
        case .claude: "Claude and Claude Code draw on this one allowance."
        case .chatgpt: "ChatGPT and Codex draw on this one Work allowance. Regular Chat and Voice limits are not included."
        default: nil
        }
    }
    public var subtitle: String {
        switch self {
        case .claude: "Claude and Claude Code"
        case .chatgpt: "ChatGPT and Codex"
        case .codex: "Build without surprises"
        case .claudeCode: "Keep your flow going"
        }
    }
    public var accountURL: URL {
        let address = switch self {
        case .claude, .claudeCode: "https://claude.ai/settings/usage"
        // The Work allowance is the one Codex meters, so its page is the one that
        // shows the number Brim shows.
        case .chatgpt, .codex: "https://chatgpt.com/codex/settings/usage"
        }
        return URL(string: address)!
    }
}

public enum UsageSeverity: String, Codable, Sendable {
    case normal, warning, critical
    public init(reported: String?) {
        switch reported?.lowercased() {
        case "warning": self = .warning
        case "critical", "severe", "exceeded": self = .critical
        default: self = .normal
        }
    }
}

public struct UsageWindow: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var durationMinutes: Int?
    /// The provider's own severity for this window, when it reports one.
    public var severity: UsageSeverity = .normal
    /// What the window is scoped to, when it is narrower than the whole plan:
    /// a model name, for instance. Nil means it covers everything.
    public var scopeLabel: String?
    /// The provider marks the window currently doing the limiting. The headline
    /// number follows this, so it stops changing identity between refreshes.
    public var isActive = false
    /// True when the value was derived locally rather than reported. Anything
    /// estimated has to say so wherever it is shown.
    public var isEstimated = false
    public init(id: String, title: String, usedPercent: Double, resetsAt: Date? = nil,
                durationMinutes: Int? = nil, severity: UsageSeverity = .normal,
                scopeLabel: String? = nil, isActive: Bool = false, isEstimated: Bool = false) {
        self.id = id; self.title = title; self.usedPercent = usedPercent
        self.resetsAt = resetsAt; self.durationMinutes = durationMinutes
        self.severity = severity; self.scopeLabel = scopeLabel
        self.isActive = isActive; self.isEstimated = isEstimated
    }
    public var fraction: Double { max(0, min(100, usedPercent)) / 100 }
    public func hasExpired(at now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }
    public func resetDescription(at now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds <= 0 { return "Awaiting new window" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "Resets in \(minutes)m" }
        if minutes < 1440 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets \(resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}

public enum UsageSource: String, Codable, Sendable {
    case codex, chatgptWork, claudeBridge, claudeCache, claudeLive, manual
    public var label: String {
        switch self {
        case .codex: "Live · Codex"
        case .chatgptWork: "Live · shared with Codex"
        case .claudeBridge: "Claude Code bridge"
        case .claudeCache: "Claude Code cache"
        case .claudeLive: "Live · Claude"
        case .manual: "Manual entry"
        }
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var provider: Provider
    public var windows: [UsageWindow]
    public var source: UsageSource
    public var updatedAt: Date
    public var plan: String?
    public init(provider: Provider, windows: [UsageWindow], source: UsageSource, updatedAt: Date = Date(), plan: String? = nil) {
        self.provider = provider; self.windows = windows; self.source = source
        self.updatedAt = updatedAt; self.plan = plan
    }
    public func primary(at now: Date = Date()) -> UsageWindow? { windows.first { !$0.hasExpired(at: now) } }

    /// The window the headline number represents.
    ///
    /// Prefers the window the provider says is actually limiting, so the big number
    /// keeps a fixed identity instead of quietly switching between "session" and
    /// "weekly" as one overtakes the other. A percentage that changes meaning
    /// between refreshes is worse than no percentage.
    public func headline(at now: Date = Date()) -> UsageWindow? {
        windows.first { $0.isActive && !$0.hasExpired(at: now) }
            ?? windows.first { !$0.hasExpired(at: now) }
    }

    public func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) > (source == .manual ? 86400 : 600)
    }

    /// ChatGPT Work and Codex consume the same allowance. This is not a
    /// measurement of regular Chat or Voice usage. Keep the original timestamp
    /// and reset windows so a copied reading never becomes artificially fresh.
    /// Source: https://learn.chatgpt.com/docs/pricing
    public func sharedChatGPTWork() -> UsageSnapshot? {
        guard provider == .codex, source == .codex, !windows.isEmpty,
              windows.allSatisfy({ $0.usedPercent.isFinite && $0.usedPercent >= 0 }) else { return nil }
        return UsageSnapshot(provider: .chatgpt, windows: windows, source: .chatgptWork,
                             updatedAt: updatedAt, plan: plan)
    }
}

public enum UsageParseError: LocalizedError {
    case missingLimits, invalidData
    public var errorDescription: String? {
        switch self {
        case .missingLimits: "No usage windows were reported by this account."
        case .invalidData: "The usage data could not be read."
        }
    }
}

public enum UsageParser {
    /// The Codex app-server's rate limits.
    ///
    /// The account's own allowance is the `codex` bucket, which reports a `primary`
    /// window and sometimes a shorter `secondary` one. Alongside it the reply can carry
    /// model-scoped siblings, `codex_bengalfox` named "GPT-5.3-Codex-Spark", say,
    /// which are limits on this same allowance, exactly as Claude reports a per-model
    /// weekly beside its overall one. Those are read too, and labelled with the model
    /// they belong to.
    ///
    /// Buckets that are *not* Codex are still refused outright. A different metered
    /// product must never be presented as this one's usage.
    public static func codex(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageParseError.invalidData }
        let root = json["result"] as? [String: Any] ?? json
        var bucket: [String: Any]?
        var scoped: [(key: String, bucket: [String: Any])] = []
        if let buckets = root["rateLimitsByLimitId"] as? [String: [String: Any]], !buckets.isEmpty {
            bucket = buckets["codex"]
            scoped = buckets
                .filter { $0.key != "codex" && $0.key.hasPrefix("codex_") && $0.value["limitName"] is String }
                .sorted { $0.key < $1.key }
                .map { ($0.key, $0.value) }
        } else if let legacy = root["rateLimits"] as? [String: Any],
                  legacy["limitId"] as? String == nil || legacy["limitId"] as? String == "codex" {
            bucket = legacy
        }
        guard let bucket else { throw UsageParseError.missingLimits }
        if let limitID = bucket["limitId"] as? String, limitID != "codex" { throw UsageParseError.missingLimits }

        var windows = codexWindows(in: bucket, idPrefix: "", scope: nil)
        for entry in scoped {
            windows += codexWindows(in: entry.bucket, idPrefix: entry.key + ":",
                                    scope: entry.bucket["limitName"] as? String)
        }
        guard !windows.isEmpty else { throw UsageParseError.missingLimits }
        return UsageSnapshot(provider: .codex, windows: windows, source: .codex, updatedAt: now, plan: bucket["planType"] as? String)
    }

    /// The `primary` and `secondary` windows of one bucket. A missing percentage is
    /// unknown, so that window is dropped rather than reported as zero.
    private static func codexWindows(in bucket: [String: Any], idPrefix: String, scope: String?) -> [UsageWindow] {
        ["primary", "secondary"].compactMap { key -> UsageWindow? in
            guard let window = bucket[key] as? [String: Any],
                  let used = number(window["usedPercent"]), used >= 0 else { return nil }
            let duration = number(window["windowDurationMins"]).map(Int.init)
            let period = duration.map { $0 >= 10080 ? "weekly" : $0 >= 1440 ? "daily" : "session" }
                ?? (key == "primary" ? "session" : "secondary")
            let title: String
            if let scope {
                title = "\(scope) · \(period)"
            } else {
                switch period {
                case "weekly": title = "Weekly limit"
                case "daily": title = "Daily limit"
                case "session": title = "Current session"
                default: title = "Secondary limit"
                }
            }
            return UsageWindow(id: idPrefix + key, title: title, usedPercent: used,
                               resetsAt: number(window["resetsAt"]).map(Date.init(timeIntervalSince1970:)),
                               durationMinutes: duration, scopeLabel: scope)
        }
    }

    /// Anthropic's live usage response.
    ///
    /// The limits sit at the top level of the reply, in the same shape the cache
    /// nests under `utilization`, so both go through one reader. An earlier version
    /// of this function looked for a `rate_limits` object with `used_percentage` and
    /// epoch timestamps; the endpoint returns nothing of the sort, so every live
    /// fetch parsed to zero windows and the app silently showed the stale cache.
    public static func claude(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageParseError.invalidData }
        // An empty update explicitly clears older quotas; it must not preserve a past account's numbers.
        return UsageSnapshot(provider: .claudeCode, windows: ClaudeUsageFormat.windows(in: root),
                             source: .claudeBridge, updatedAt: now)
    }

    static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull), let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}

import CoreFoundation
