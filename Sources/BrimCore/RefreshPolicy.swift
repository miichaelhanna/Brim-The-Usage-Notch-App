import Foundation

/// What the app knows about one provider's refresh history.
///
/// Persisted, so a provider that was backing off does not get hammered again the
/// moment the app restarts. A restart loop would otherwise reset every deadline and
/// turn a rate limit into a much worse one.
public struct ProviderRefreshState: Codable, Equatable, Sendable {
    public var lastAttempt: Date?
    public var consecutiveFailures: Int
    public var retryDeadline: Date?

    public init(lastAttempt: Date? = nil, consecutiveFailures: Int = 0, retryDeadline: Date? = nil) {
        self.lastAttempt = lastAttempt
        self.consecutiveFailures = consecutiveFailures
        self.retryDeadline = retryDeadline
    }
}

/// Decides when a provider may be asked again.
///
/// Three rules: a normal cadence while the user is around, a slower one when they are
/// not, and exponential backoff after failures. Previously the app had none of these.
/// It retried on the same one-minute tick whether things were working or not.
///
/// The idle cadence is what a usage meter can afford to relax to, not what it aims
/// for: anything that puts a number in front of someone refreshes first, so the
/// slower tick only ever governs a screen nobody is looking at.
public struct RefreshPolicy: Equatable, Sendable {
    public var activeInterval: TimeInterval
    public var idleInterval: TimeInterval
    public var idleAfter: TimeInterval
    public var firstBackoff: TimeInterval
    public var maxBackoff: TimeInterval

    public init(activeInterval: TimeInterval = 60, idleInterval: TimeInterval = 300,
                idleAfter: TimeInterval = 600, firstBackoff: TimeInterval = 60,
                maxBackoff: TimeInterval = 1800) {
        self.activeInterval = activeInterval
        self.idleInterval = idleInterval
        self.idleAfter = idleAfter
        self.firstBackoff = firstBackoff
        self.maxBackoff = maxBackoff
    }

    public func isIdle(lastActivity: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastActivity) >= idleAfter
    }

    public func interval(lastActivity: Date, now: Date) -> TimeInterval {
        isIdle(lastActivity: lastActivity, now: now) ? idleInterval : activeInterval
    }

    /// Doubling delay, capped. The exponent is clamped before it is used so a long
    /// outage cannot overflow the multiplication into infinity.
    public func retryDeadline(consecutiveFailures: Int, from now: Date) -> Date? {
        guard consecutiveFailures > 0 else { return nil }
        let exponent = min(consecutiveFailures - 1, 16)
        let delay = min(firstBackoff * pow(2, Double(exponent)), maxBackoff)
        return now.addingTimeInterval(delay)
    }

    public func shouldAttempt(_ state: ProviderRefreshState, lastActivity: Date, now: Date) -> Bool {
        if let deadline = state.retryDeadline, now < deadline { return false }
        guard let last = state.lastAttempt else { return true }
        // A clock that jumped backwards would otherwise stall refreshing indefinitely.
        guard now >= last else { return true }
        return now.timeIntervalSince(last) >= interval(lastActivity: lastActivity, now: now)
    }

    /// The state to record after an attempt. A success clears the backoff entirely.
    public func state(after state: ProviderRefreshState, succeeded: Bool, now: Date) -> ProviderRefreshState {
        guard !succeeded else { return ProviderRefreshState(lastAttempt: now) }
        let failures = state.consecutiveFailures + 1
        return ProviderRefreshState(lastAttempt: now, consecutiveFailures: failures,
                                    retryDeadline: retryDeadline(consecutiveFailures: failures, from: now))
    }
}
