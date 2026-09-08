import Foundation

/// One thing the interface can show a ring for.
///
/// The notch, the dashboard and the menu list built-in providers and user-described
/// tools side by side, so they need a single identity covering both. `Provider` stays
/// what it was, the set of sources this app knows how to read, and this is only what
/// it takes to *display* one of them next to a tool someone added themselves.
public struct TrackedTool: Identifiable, Hashable, Sendable {
    /// A provider's raw value, or `custom:<descriptor id>`. Used as a storage key, so
    /// the two namespaces must not be able to collide.
    public let id: String
    public let name: String
    public let subtitle: String
    /// What this figure does not cover, when that isn't obvious.
    public let scopeNote: String?
    public let accountURL: URL?
    /// The provider behind this, or nil when the tool was described in a file.
    public let builtin: Provider?

    public static let describedPrefix = "custom:"

    public init(_ provider: Provider) {
        id = provider.rawValue
        name = provider.usageName
        subtitle = provider.subtitle
        scopeNote = provider.usageScopeNote
        accountURL = provider.accountURL
        builtin = provider
    }

    public init(_ descriptor: ToolDescriptor) {
        id = Self.describedPrefix + descriptor.id
        name = descriptor.name
        subtitle = "Added on this Mac"
        scopeNote = descriptor.note
        accountURL = nil
        builtin = nil
    }

    public var isDescribed: Bool { builtin == nil }

    /// The descriptor's own id, for a described tool.
    public var descriptorID: String? {
        isDescribed ? String(id.dropFirst(Self.describedPrefix.count)) : nil
    }

    /// Stands in for a brand mark. A tool someone added has no logo the app can draw,
    /// and inventing one would be worse than initials that are obviously initials.
    public var monogram: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.count >= 2
            ? words.prefix(2).compactMap(\.first)
            : Array(name.filter { $0.isLetter || $0.isNumber }.prefix(2))
        return String(letters).uppercased()
    }

    public var linkHint: String {
        builtin?.usageLinkHint ?? "Read from a file on this Mac"
    }
}

/// A reading as the interface consumes it.
///
/// A built-in provider's reading arrives as a `UsageSnapshot`, which is tied to
/// `Provider`; a described tool's arrives as a handful of windows read out of a file.
/// The views want the same four things from either, so they take this.
public struct ToolReading: Equatable, Sendable {
    public var windows: [UsageWindow]
    /// Allowances reported as a count rather than a proportion. See `UsageCount`:
    /// a provider that will not say what the allowance was cannot be drawn as a ring.
    public var counts: [UsageCount]
    public var sourceLabel: String
    public var updatedAt: Date
    /// How long a reading from this source stays current. Beyond it, the app says
    /// "last known" rather than implying the number is live.
    public var freshFor: TimeInterval
    public init(windows: [UsageWindow], counts: [UsageCount] = [], sourceLabel: String,
                updatedAt: Date, freshFor: TimeInterval = 600) {
        self.windows = windows; self.counts = counts; self.sourceLabel = sourceLabel
        self.updatedAt = updatedAt; self.freshFor = freshFor
    }

    public init(_ snapshot: UsageSnapshot) {
        self.init(windows: snapshot.windows, counts: snapshot.counts,
                  sourceLabel: snapshot.source.label,
                  updatedAt: snapshot.updatedAt,
                  freshFor: snapshot.source == .manual ? 86400 : 600)
    }

    /// Whether this reading says anything at all, in either shape.
    public var hasReading: Bool { !windows.isEmpty || !counts.isEmpty }

    public func primary(at now: Date = Date()) -> UsageWindow? {
        windows.first { !$0.hasExpired(at: now) }
    }

    public func headline(at now: Date = Date()) -> UsageWindow? {
        windows.first { $0.isActive && !$0.hasExpired(at: now) } ?? primary(at: now)
    }

    public func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) > freshFor
    }
}
