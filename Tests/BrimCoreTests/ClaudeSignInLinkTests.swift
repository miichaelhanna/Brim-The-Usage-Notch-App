import XCTest
@testable import BrimCore

final class ClaudeSignInLinkTests: XCTestCase {
    func testTheFallbackLinkClaudeCodePrints() {
        let text = "Opening browser to sign in…\nIf the browser didn't open, visit: "
            + "https://claude.ai/oauth/authorize?code=true&client_id=x&state=y\nPaste code here if prompted > "
        XCTAssertEqual(ClaudeSignInLink.find(in: text)?.host, "claude.ai")
    }

    func testNothingUntilTheLinkArrives() {
        XCTAssertNil(ClaudeSignInLink.find(in: "Opening browser to sign in…\n"))
    }

    /// Only Anthropic's own sign-in is offered as a button, whatever else is printed.
    func testALinkAnywhereElseIsNeverOffered() {
        XCTAssertNil(ClaudeSignInLink.find(in: "visit: https://claude.ai.example.com/login"))
        XCTAssertNil(ClaudeSignInLink.find(in: "visit: https://notclaude.ai/login"))
        XCTAssertNil(ClaudeSignInLink.find(in: "visit: http://claude.ai/login"), "never over plain http")
        XCTAssertEqual(ClaudeSignInLink.find(in: "visit: https://console.anthropic.com/oauth")?.host,
                       "console.anthropic.com")
    }
}
