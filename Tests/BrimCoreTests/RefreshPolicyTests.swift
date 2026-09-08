import XCTest
@testable import BrimCore

final class RefreshPolicyTests: XCTestCase {
    private let policy = RefreshPolicy()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstAttemptIsAlwaysAllowed() {
        XCTAssertTrue(policy.shouldAttempt(ProviderRefreshState(), lastActivity: now, now: now))
    }

    func testWaitsTheActiveIntervalWhileTheUserIsAround() {
        let state = ProviderRefreshState(lastAttempt: now)
        XCTAssertFalse(policy.shouldAttempt(state, lastActivity: now, now: now.addingTimeInterval(59)))
        XCTAssertTrue(policy.shouldAttempt(state, lastActivity: now, now: now.addingTimeInterval(60)))
    }

    func testSlowsDownWhenIdle() {
        let state = ProviderRefreshState(lastAttempt: now)
        let later = now.addingTimeInterval(120)
        // The last activity was long ago, so the idle cadence applies.
        XCTAssertTrue(policy.isIdle(lastActivity: now.addingTimeInterval(-3600), now: later))
        XCTAssertFalse(policy.shouldAttempt(state, lastActivity: now.addingTimeInterval(-3600), now: later))
        XCTAssertTrue(policy.shouldAttempt(state, lastActivity: now.addingTimeInterval(-3600),
                                           now: now.addingTimeInterval(300)))
    }

    func testBackoffDoublesAndIsCapped() throws {
        var state = ProviderRefreshState()
        var expected: [TimeInterval] = []
        for _ in 0..<8 {
            state = policy.state(after: state, succeeded: false, now: now)
            expected.append(try XCTUnwrap(state.retryDeadline).timeIntervalSince(now))
        }
        XCTAssertEqual(Array(expected.prefix(4)), [60, 120, 240, 480])
        XCTAssertEqual(expected.last, policy.maxBackoff, "backoff stops growing at the cap")
        XCTAssertTrue(expected.allSatisfy { $0 <= policy.maxBackoff })
    }

    func testNoAttemptsBeforeTheRetryDeadline() {
        let state = policy.state(after: ProviderRefreshState(), succeeded: false, now: now)
        XCTAssertFalse(policy.shouldAttempt(state, lastActivity: now, now: now.addingTimeInterval(59)))
        XCTAssertTrue(policy.shouldAttempt(state, lastActivity: now, now: now.addingTimeInterval(61)))
    }

    func testSuccessClearsTheBackoff() {
        var state = ProviderRefreshState()
        for _ in 0..<5 { state = policy.state(after: state, succeeded: false, now: now) }
        XCTAssertGreaterThan(state.consecutiveFailures, 0)
        state = policy.state(after: state, succeeded: true, now: now)
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertNil(state.retryDeadline)
    }

    /// A deadline must survive a relaunch, or restarting turns a rate limit into a
    /// tighter one.
    func testStateRoundTripsThroughCoding() throws {
        let state = policy.state(after: ProviderRefreshState(), succeeded: false, now: now)
        let decoded = try JSONDecoder().decode(ProviderRefreshState.self,
                                               from: try JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }

    func testClockMovingBackwardsDoesNotStallRefreshing() {
        let state = ProviderRefreshState(lastAttempt: now)
        XCTAssertTrue(policy.shouldAttempt(state, lastActivity: now, now: now.addingTimeInterval(-5000)))
    }
}
