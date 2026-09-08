import XCTest
@testable import BrimCore

final class SharedOpenAIUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testWorkUsesOnlyTheVerifiedSharedBucketAndPreservesFreshness() throws {
        let payload = Data(#"{"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":24,"windowDurationMins":10080,"resetsAt":1800003600},"planType":"pro"},"codex_bengalfox":{"primary":{"usedPercent":92}}}}"#.utf8)
        let codex = try UsageParser.codex(payload, now: now)
        let work = try XCTUnwrap(codex.sharedChatGPTWork())
        XCTAssertEqual(work.provider, .chatgpt)
        XCTAssertEqual(work.source, .chatgptWork)
        XCTAssertEqual(work.windows, codex.windows)
        XCTAssertEqual(work.windows.map(\.usedPercent), [24])
        XCTAssertEqual(work.updatedAt, now)
        XCTAssertEqual(work.plan, "pro")
        XCTAssertTrue(work.isStale(at: now.addingTimeInterval(601)))
        XCTAssertNil(work.primary(at: now.addingTimeInterval(3600)))
    }

    func testManualAndOtherProvidersCannotBecomeLiveWorkReadings() {
        let window = UsageWindow(id: "primary", title: "Weekly limit", usedPercent: 24)
        for source in [UsageSource.manual, .claudeBridge, .chatgptWork] {
            XCTAssertNil(UsageSnapshot(provider: .codex, windows: [window], source: source).sharedChatGPTWork())
        }
        for provider in Provider.allCases where provider != .codex {
            XCTAssertNil(UsageSnapshot(provider: provider, windows: [window], source: .codex).sharedChatGPTWork())
        }
    }

    func testMissingOrInvalidQuotaIsNeverSynthesizedAsZero() {
        XCTAssertNil(UsageSnapshot(provider: .codex, windows: [], source: .codex).sharedChatGPTWork())
        for used in [-1.0, .infinity, .nan] {
            let invalid = UsageWindow(id: "primary", title: "Weekly limit", usedPercent: used)
            XCTAssertNil(UsageSnapshot(provider: .codex, windows: [invalid], source: .codex).sharedChatGPTWork())
        }
        let reportedZero = UsageWindow(id: "primary", title: "Weekly limit", usedPercent: 0)
        XCTAssertEqual(UsageSnapshot(provider: .codex, windows: [reportedZero], source: .codex)
            .sharedChatGPTWork()?.windows.first?.usedPercent, 0)
    }

    func testContradictoryBucketIdentityCannotBeShared() {
        let payload = Data(#"{"rateLimitsByLimitId":{"codex":{"limitId":"different-product","primary":{"usedPercent":24}}}}"#.utf8)
        XCTAssertThrowsError(try UsageParser.codex(payload))
    }

    func testWorkScopeSurvivesSerialization() throws {
        let work = try XCTUnwrap(UsageSnapshot(provider: .codex,
            windows: [UsageWindow(id: "primary", title: "Weekly limit", usedPercent: 24)],
            source: .codex, updatedAt: now).sharedChatGPTWork())
        XCTAssertEqual(try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(work)), work)
        XCTAssertEqual(Provider.chatgpt.usageName, "ChatGPT")
        XCTAssertTrue(Provider.chatgpt.usageScopeNote?.contains("Work") == true)
        XCTAssertEqual(work.source.label, "Live · shared with Codex")
        XCTAssertNotNil(Provider.chatgpt.usageScopeNote)
    }
}
