import XCTest
@testable import BrimCore

final class PerplexityUsageTests: XCTestCase {
    /// Builds a preferences file the shape the Perplexity Mac app actually writes: a
    /// binary plist whose usage value is a *string* of JSON stored as data, so the
    /// reading is decoded twice.
    private func preferences(remainingUsage: String? = nil, user: String? = nil,
                             asString: Bool = false) -> Data {
        var plist: [String: Any] = ["GID_AppHasRunBefore": true, "currentSearchModeID": "search"]
        if let remainingUsage {
            plist["remainingUsage"] = asString ? remainingUsage : Data(remainingUsage.utf8)
        }
        if let user { plist["current_user__data"] = Data(user.utf8) }
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    /// The exact payload read off a real free-tier install, 2026-09-09.
    private let live = """
    {"modes":{"pro_search":{"available":true,"remaining_detail":{"remaining":4,"kind":"exact"}},\
    "agentic_research":{"available":false,"remaining_detail":{"remaining":0,"kind":"exact"}},\
    "research":{"remaining_detail":{"kind":"exact","remaining":0},"available":false}},\
    "free_queries":{"remaining_detail":{"kind":"not_provided"},"available":true}}
    """

    // MARK: - Reading the file

    func testReadsTheCountsARealInstallWrites() throws {
        let counts = try PerplexityUsage.counts(preferences(remainingUsage: live))
        XCTAssertEqual(counts.map(\.title), ["Pro searches", "Deep research", "Model council"])
        XCTAssertEqual(counts[0].remaining, 4)
    }

    /// The whole point of the adapter: what is left, never a percentage.
    func testAnAvailableModeKeepsItsExactRemaining() throws {
        let counts = try PerplexityUsage.counts(preferences(remainingUsage: live))
        XCTAssertEqual(counts.first { $0.id == "pro_search" }?.detail, "4 left")
    }

    /// Perplexity reports "never on your plan" and "spent to the last query" the same
    /// way, both as an unavailable zero. Neither claim is made, so no number is shown.
    func testAnUnavailableModeReportsNoNumberRatherThanZero() throws {
        let counts = try PerplexityUsage.counts(preferences(remainingUsage: live))
        for id in ["research", "agentic_research"] {
            let count = counts.first { $0.id == id }
            XCTAssertNil(count?.remaining, id)
            XCTAssertEqual(count?.detail, "Unavailable", id)
        }
    }

    /// A missing count is unknown, not none left.
    func testAModeThatReportsNoNumberIsLeftOut() throws {
        let counts = try PerplexityUsage.counts(preferences(remainingUsage: """
        {"modes":{"pro_search":{"available":true,"remaining_detail":{"kind":"not_provided"}}}}
        """))
        XCTAssertEqual(counts, [])
    }

    func testKeepsPerplexitysOwnOrderAndSendsUnknownModesLast() throws {
        let counts = try PerplexityUsage.counts(preferences(remainingUsage: """
        {"modes":{"aardvark_mode":{"available":true,"remaining_detail":{"remaining":9,"kind":"exact"}},\
        "research":{"available":true,"remaining_detail":{"remaining":2,"kind":"exact"}},\
        "pro_search":{"available":true,"remaining_detail":{"remaining":7,"kind":"exact"}}}}
        """))
        XCTAssertEqual(counts.map(\.id), ["pro_search", "research", "aardvark_mode"])
        XCTAssertEqual(counts.last?.title, "Aardvark Mode")
    }

    func testAcceptsTheUsageValueStoredAsAStringRatherThanData() throws {
        let counts = try PerplexityUsage.counts(preferences(remainingUsage: live, asString: true))
        XCTAssertEqual(counts.first?.remaining, 4)
    }

    // MARK: - When it cannot be read

    func testAFileWithNoUsageBlockIsReportedAsMissingRatherThanEmpty() {
        XCTAssertThrowsError(try PerplexityUsage.counts(preferences())) { error in
            XCTAssertEqual(error as? UsageParseError, .missingLimits)
        }
    }

    func testSomethingThatIsNotAPropertyListIsRefused() {
        XCTAssertThrowsError(try PerplexityUsage.counts(Data("not a plist".utf8))) { error in
            XCTAssertEqual(error as? UsageParseError, .invalidData)
        }
    }

    /// An account with nothing metered is a real state, not a broken read.
    func testAUsageBlockWithNoModesIsEmptyRatherThanAFailure() throws {
        XCTAssertEqual(try PerplexityUsage.counts(preferences(remainingUsage: #"{"free_queries":{}}"#)), [])
    }

    // MARK: - Plan

    func testReadsThePlanWhenThereIsOne() {
        let data = preferences(remainingUsage: live, user: #"{"subscription":{"tier":"pro"}}"#)
        XCTAssertEqual(PerplexityUsage.plan(data), "Pro")
    }

    /// "none" is a free account, which is not a plan name worth printing.
    func testAFreeAccountHasNoPlanToShow() {
        let data = preferences(remainingUsage: live, user: #"{"subscription":{"tier":"none"}}"#)
        XCTAssertNil(PerplexityUsage.plan(data))
        XCTAssertNil(PerplexityUsage.plan(preferences(remainingUsage: live)))
    }
}

final class CountReadingTests: XCTestCase {
    private let counts = [UsageCount(id: "pro_search", title: "Pro searches", remaining: 4)]

    /// A count-only reading has to count as a reading, or every "is there anything to
    /// show" check treats Perplexity as empty and offers to set it up again.
    func testASnapshotOfOnlyCountsCountsAsAReading() {
        let snapshot = UsageSnapshot(provider: .perplexity, windows: [], counts: counts,
                                     source: .perplexityApp)
        XCTAssertTrue(snapshot.hasReading)
        XCTAssertTrue(ToolReading(snapshot).hasReading)
        XCTAssertEqual(ToolReading(snapshot).counts, counts)
    }

    func testAnEmptySnapshotIsStillEmpty() {
        XCTAssertFalse(UsageSnapshot(provider: .perplexity, windows: [], source: .perplexityApp).hasReading)
    }

    /// Readings cached by a build that predates counts must still load, rather than
    /// being thrown away and blanking the rings on first launch after an update.
    func testAReadingSavedBeforeCountsExistedStillDecodes() throws {
        let saved = """
        {"provider":"codex","windows":[],"source":"codex","updatedAt":0}
        """
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(saved.utf8))
        XCTAssertEqual(snapshot.counts, [])
        XCTAssertEqual(snapshot.provider, .codex)
    }

    func testCountsSurviveASaveAndLoad() throws {
        let snapshot = UsageSnapshot(provider: .perplexity, windows: [], counts: counts,
                                     source: .perplexityApp)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.counts, counts)
    }
}
