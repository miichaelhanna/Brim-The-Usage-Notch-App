import XCTest
@testable import BrimCore

final class CredentialRenewalTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_757_332_800)

    /// The credential that just failed must not read as news, or the app retries it
    /// immediately, fails again, and never stops.
    func testTheFirstSightingIsNeverARenewal() {
        var renewal = CredentialRenewal()
        XCTAssertFalse(renewal.noticed(noon))
        XCTAssertFalse(renewal.noticed(noon), "the same login, looked at twice, is still the same login")
    }

    func testAWriteAfterTheFailedOneIsNoticedOnce() {
        var renewal = CredentialRenewal()
        _ = renewal.noticed(noon)
        XCTAssertTrue(renewal.noticed(noon.addingTimeInterval(60)))
        XCTAssertFalse(renewal.noticed(noon.addingTimeInterval(60)), "noticed once, not on every look after")
        XCTAssertTrue(renewal.noticed(noon.addingTimeInterval(120)))
    }

    /// Signing out and back in writes a fresh item rather than rewriting the old one.
    func testAppearingFromNothingCountsAsARenewal() {
        var renewal = CredentialRenewal()
        XCTAssertFalse(renewal.noticed(nil))
        XCTAssertTrue(renewal.noticed(noon))
    }

    func testNothingThereIsNotARenewal() {
        var renewal = CredentialRenewal()
        _ = renewal.noticed(noon)
        XCTAssertFalse(renewal.noticed(nil), "a login that has gone away is not a new one")
        XCTAssertTrue(renewal.noticed(noon), "and it coming back is")
    }

    /// A Keychain item restored from a backup carries an older date than the one that
    /// failed. It is still a different credential, and still worth the one attempt.
    func testAnOlderWriteIsStillADifferentCredential() {
        var renewal = CredentialRenewal()
        _ = renewal.noticed(noon)
        XCTAssertTrue(renewal.noticed(noon.addingTimeInterval(-3600)))
        XCTAssertFalse(renewal.noticed(noon.addingTimeInterval(-3600)))
    }

    func testResetForgetsWhatItSaw() {
        var renewal = CredentialRenewal()
        _ = renewal.noticed(noon)
        renewal.reset()
        XCTAssertFalse(renewal.noticed(noon.addingTimeInterval(600)), "a fresh start looks for the first time again")
    }
}
