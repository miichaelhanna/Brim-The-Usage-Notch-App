import XCTest
@testable import BrimCore

final class ClaudeLoginFormatTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testClaudeCodesOwnFormat() {
        let login = ClaudeLoginFormat.parse(data(
            #"{"claudeAiOauth":{"accessToken":"a","expiresAt":1757332800000,"subscriptionType":"max"}}"#))
        XCTAssertEqual(login, .init(accessToken: "a",
                                    expiresAt: Date(timeIntervalSince1970: 1_757_332_800),
                                    subscription: "max"))
    }

    /// An expiry that is missing is unknown, not a reason to call the login absent.
    /// The server's reply decides whether it still works.
    func testAMissingExpiryStillFindsTheLogin() {
        let login = ClaudeLoginFormat.parse(data(#"{"claudeAiOauth":{"accessToken":"a"}}"#))
        XCTAssertEqual(login?.accessToken, "a")
        XCTAssertNil(login?.expiresAt)
    }

    func testAnExpiryInSecondsIsNotReadAsMilliseconds() {
        let login = ClaudeLoginFormat.parse(data(#"{"claudeAiOauth":{"accessToken":"a","expiresAt":1757332800}}"#))
        XCTAssertEqual(login?.expiresAt, Date(timeIntervalSince1970: 1_757_332_800))
    }

    func testAnExpiryWrittenAsText() {
        XCTAssertEqual(ClaudeLoginFormat.parse(data(
            #"{"claudeAiOauth":{"accessToken":"a","expiresAt":"1757332800000"}}"#))?.expiresAt,
                       Date(timeIntervalSince1970: 1_757_332_800))
        XCTAssertEqual(ClaudeLoginFormat.parse(data(
            #"{"claudeAiOauth":{"accessToken":"a","expiresAt":"2025-09-08T12:00:00Z"}}"#))?.expiresAt,
                       Date(timeIntervalSince1970: 1_757_332_800))
    }

    func testALoginAtTheTopLevel() {
        XCTAssertEqual(ClaudeLoginFormat.parse(data(#"{"accessToken":"a","expiresAt":1757332800000}"#))?.accessToken, "a")
    }

    func testJSONStoredAsItsOwnHex() {
        let json = #"{"claudeAiOauth":{"accessToken":"a","expiresAt":1757332800000}}"#
        let hex = json.utf8.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(ClaudeLoginFormat.parse(data(hex))?.accessToken, "a")
    }

    func testNoTokenIsNoLogin() {
        XCTAssertNil(ClaudeLoginFormat.parse(data(#"{"claudeAiOauth":{"expiresAt":1757332800000}}"#)))
        XCTAssertNil(ClaudeLoginFormat.parse(data(#"{"claudeAiOauth":{"accessToken":""}}"#)))
        XCTAssertNil(ClaudeLoginFormat.parse(data("not json and not hex")))
    }
}
