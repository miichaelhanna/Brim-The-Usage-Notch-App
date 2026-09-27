import XCTest
@testable import BrimCore

final class ClaudeCodeReleaseTests: XCTestCase {
    func testAVersionIsReadAndAnythingElseIsRefused() {
        XCTAssertEqual(ClaudeCodeRelease.version(Data("2.1.283\n".utf8)), "2.1.283")
        XCTAssertNil(ClaudeCodeRelease.version(Data("<html>Not available</html>".utf8)))
        XCTAssertNil(ClaudeCodeRelease.version(Data("../../evil".utf8)))
        XCTAssertNil(ClaudeCodeRelease.version(Data()))
    }

    func testTheChecksumForThisPlatform() {
        let sum = String(repeating: "ab", count: 32)
        let manifest = Data(#"{"platforms":{"darwin-arm64":{"binary":"claude","checksum":"\#(sum)","size":1},"darwin-x64":{"checksum":"00"}}}"#.utf8)
        XCTAssertEqual(ClaudeCodeRelease.checksum(manifest, platform: "darwin-arm64"), sum)
        XCTAssertNil(ClaudeCodeRelease.checksum(manifest, platform: "darwin-x64"), "not a SHA-256")
        XCTAssertNil(ClaudeCodeRelease.checksum(manifest, platform: "linux-x64"))
    }

    func testRosettaGetsTheNativeBuild() {
        XCTAssertEqual(ClaudeCodeRelease.platform(arm64: true, translated: false), "darwin-arm64")
        XCTAssertEqual(ClaudeCodeRelease.platform(arm64: false, translated: true), "darwin-arm64")
        XCTAssertEqual(ClaudeCodeRelease.platform(arm64: false, translated: false), "darwin-x64")
    }

    func testTheURLsTheInstallerScriptUses() {
        XCTAssertEqual(ClaudeCodeRelease.binary("2.1.283", platform: "darwin-arm64").absoluteString,
                       "https://downloads.claude.ai/claude-code-releases/2.1.283/darwin-arm64/claude")
        XCTAssertEqual(ClaudeCodeRelease.manifest("2.1.283").absoluteString,
                       "https://downloads.claude.ai/claude-code-releases/2.1.283/manifest.json")
    }
}
