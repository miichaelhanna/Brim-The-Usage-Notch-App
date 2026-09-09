import XCTest
@testable import BrimCore

final class UsageParserTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCodexPrefersNamedBucketOverLegacy() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":63,"windowDurationMins":10080},"planType":"pro"},"other":{"primary":{"usedPercent":80}}}}"#.utf8)
        let snapshot = try UsageParser.codex(data, now: now)
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [25, 63])
        XCTAssertEqual(snapshot.windows.last?.title, "Weekly limit")
        XCTAssertEqual(snapshot.windows.first?.resetsAt, now.addingTimeInterval(3600))
        XCTAssertEqual(snapshot.plan, "pro")
    }

    func testCodexLegacyAndMissingSecondary() throws {
        let snapshot = try UsageParser.codex(Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":0},"secondary":null}}}"#.utf8))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent, 0)
        XCTAssertNil(snapshot.windows[0].resetsAt)
    }

    func testMissingIsNotZero() {
        for json in [#"{"rateLimits":null}"#, #"{"rateLimits":{"primary":{"usedPercent":null}}}"#, #"{"rateLimits":{"primary":{"usedPercent":true}}}"#, #"{"rateLimits":{"primary":{"usedPercent":-1}}}"#] {
            XCTAssertThrowsError(try UsageParser.codex(Data(json.utf8)))
        }
    }

    func testNeverLabelsAnotherProductAsCodex() {
        XCTAssertThrowsError(try UsageParser.codex(Data(#"{"rateLimitsByLimitId":{"chatgpt":{"primary":{"usedPercent":20}}},"rateLimits":{"primary":{"usedPercent":99}}}"#.utf8)))
        XCTAssertThrowsError(try UsageParser.codex(Data(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":20}}}"#.utf8)))
    }

    /// The reply carries plenty that is none of this app's business: spend, account
    /// flags, unreleased buckets under codenames. Only the limits are taken, and only
    /// the limits are ever written to disk.
    /// Captured from a real reply. The account's own bucket carries the overall limit,
    /// and model-scoped siblings carry their own, including a five-hour session window
    /// the overall bucket does not have. Reading only the first bucket hid it.
    func testCodexReadsModelScopedLimitsBesideTheAccountLimit() throws {
        let payload = Data(#"""
        {"result":{"rateLimitsByLimitId":{
          "codex":{"limitId":"codex","planType":"prolite",
                   "primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1800003600},
                   "secondary":null},
          "codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark","planType":"prolite",
                   "primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1800001800},
                   "secondary":{"usedPercent":55,"windowDurationMins":10080,"resetsAt":1800003600}}}}}
        """#.utf8)
        let snapshot = try UsageParser.codex(payload, now: now)
        XCTAssertEqual(snapshot.windows.map(\.title),
                       ["Weekly limit", "GPT-5.3-Codex-Spark · session", "GPT-5.3-Codex-Spark · weekly"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [12, 40, 55])
        XCTAssertEqual(snapshot.windows.map(\.scopeLabel), [nil, "GPT-5.3-Codex-Spark", "GPT-5.3-Codex-Spark"])
        XCTAssertEqual(Set(snapshot.windows.map(\.id)).count, 3, "ids must stay unique across buckets")
        XCTAssertEqual(snapshot.plan, "prolite", "the plan comes from the account's own bucket")
        // The whole reading is shared with ChatGPT, model-scoped windows included.
        XCTAssertEqual(try XCTUnwrap(snapshot.sharedChatGPTWork()).windows, snapshot.windows)
    }

    /// A bucket for some other metered product is still refused outright.
    func testCodexStillRefusesAnotherProductsMetering() {
        XCTAssertThrowsError(try UsageParser.codex(Data(#"""
        {"rateLimitsByLimitId":{"sora":{"limitId":"sora","limitName":"Sora","primary":{"usedPercent":90}}}}
        """#.utf8), now: now))
        // A sibling without a name is not a model limit, so it is not invented as one.
        let unnamed = try? UsageParser.codex(Data(#"""
        {"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":5,"windowDurationMins":10080}},
                                "codex_internal":{"limitId":"codex_internal","primary":{"usedPercent":99}}}}
        """#.utf8), now: now)
        XCTAssertEqual(unnamed?.windows.count, 1)
    }

    func testClaudeTakesOnlyTheLimitsAndPersistsNothingElse() throws {
        let data = Data(#"""
        {"limits":[{"kind":"weekly_all","group":"weekly","percent":7.5,"resets_at":"2030-09-13T19:00:00+00:00","severity":"normal","is_active":true}],
         "extra_usage":{"currency":"EUR","used_credits":42,"disabled_reason":"out_of_credits"},
         "member_dashboard_available":true,"juniper_tide":null,"omelette_promotional":null}
        """#.utf8)
        let snapshot = try UsageParser.claude(data, now: now)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].id, "weekly_all")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 7.5)
        let persisted = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!
        for leaked in ["EUR", "out_of_credits", "member_dashboard", "juniper", "omelette"] {
            XCTAssertFalse(persisted.contains(leaked), "\(leaked) has no business being saved")
        }
    }

    func testClaudeMissingLimitsClearsPreviousData() throws {
        let snapshot = try UsageParser.claude(Data(#"{"model":{"id":"example"}}"#.utf8))
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertNil(snapshot.primary())
    }

    func testExpiredWindowNeverLooksLikeFreshQuota() {
        let window = UsageWindow(id: "p", title: "Session", usedPercent: 73, resetsAt: now)
        let snapshot = UsageSnapshot(provider: .claude, windows: [window], source: .claudeBridge, updatedAt: now)
        XCTAssertNil(snapshot.primary(at: now))
        XCTAssertEqual(window.resetDescription(at: now), "Awaiting new window")
        XCTAssertEqual(window.usedPercent, 73)
    }

    func testClampsDrawingButPreservesOverage() {
        let window = UsageWindow(id: "spend", title: "Spend", usedPercent: 123)
        XCTAssertEqual(window.fraction, 1)
        XCTAssertEqual(window.usedPercent, 123)
    }

    func testFreshnessDependsOnSource() {
        let live = UsageSnapshot(provider: .codex, windows: [], source: .codex, updatedAt: now)
        let manual = UsageSnapshot(provider: .chatgpt, windows: [], source: .manual, updatedAt: now)
        XCTAssertTrue(live.isStale(at: now.addingTimeInterval(601)))
        XCTAssertFalse(manual.isStale(at: now.addingTimeInterval(601)))
        XCTAssertTrue(manual.isStale(at: now.addingTimeInterval(86401)))
    }

    func testCountdownRounding() {
        let window = UsageWindow(id: "p", title: "Session", usedPercent: 0, resetsAt: now.addingTimeInterval(1))
        XCTAssertEqual(window.resetDescription(at: now), "Resets in 1m")
    }

    /// Captured from a real `/api/oauth/usage` reply. The live path used to look for
    /// a `rate_limits` object with `used_percentage` and epoch timestamps, which the
    /// endpoint does not return, so every fetch parsed to nothing and answered 200.
    func testLiveResponseIsParsedInTheShapeAnthropicActuallyReturns() throws {
        let payload = Data(#"""
        {"limits":[
          {"kind":"session","group":"session","percent":55.2,"resets_at":"2030-09-08T18:00:00.000000+00:00","severity":"normal","is_active":false,"scope":null},
          {"kind":"weekly_all","group":"weekly","percent":63,"resets_at":"2030-09-13T19:00:00+00:00","severity":"normal","is_active":false,"scope":null},
          {"kind":"weekly_scoped","group":"weekly","percent":100,"resets_at":"2030-09-13T19:00:00+00:00","severity":"critical","is_active":true,
           "scope":{"model":{"display_name":"Fable","id":"claude-fable-5-1"},"surface":null}}],
         "five_hour":{"utilization":55.2,"resets_at":"2030-09-08T18:00:00+00:00","limit_dollars":null},
         "seven_day":{"utilization":63,"resets_at":"2030-09-13T19:00:00+00:00"},
         "seven_day_opus":null,"seven_day_sonnet":null,
         "extra_usage":{"is_enabled":false,"currency":"EUR","utilization":0}}
        """#.utf8)
        let snapshot = try UsageParser.claude(payload, now: now)
        XCTAssertEqual(snapshot.windows.map(\.title),
                       ["Current session", "All models · weekly", "Fable · weekly"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [55.2, 63, 100])
        // The headline follows the limit the provider marks as biting, not the first.
        let headline = try XCTUnwrap(snapshot.headline(at: now))
        XCTAssertEqual(headline.title, "Fable · weekly")
        XCTAssertEqual(headline.severity, .critical)
        XCTAssertEqual(headline.scopeLabel, "Fable")
        // ISO 8601 with and without fractional seconds both appear in one reply.
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        XCTAssertEqual(snapshot.windows[0].durationMinutes, 300)
        XCTAssertEqual(snapshot.windows[1].durationMinutes, 10080)
    }

    /// Older replies carry only the named keys. They report `utilization`, not
    /// `percent`, and the null model siblings must never become a 0% window.
    func testLiveResponseFallsBackToNamedKeysAndIgnoresNullSiblings() throws {
        let payload = Data(#"""
        {"five_hour":{"utilization":12},"seven_day":{"utilization":40},
         "seven_day_opus":null,"seven_day_sonnet":null}
        """#.utf8)
        let snapshot = try UsageParser.claude(payload, now: now)
        XCTAssertEqual(snapshot.windows.map(\.title), ["Current session", "All models · weekly"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [12, 40])
    }

    /// An account with no limits reports none. That is not an error, and it must not
    /// be filled in with zeroes.
    func testLiveResponseWithNoLimitsReportsNoWindows() throws {
        XCTAssertTrue(try UsageParser.claude(Data(#"{"limits":[]}"#.utf8), now: now).windows.isEmpty)
        XCTAssertThrowsError(try UsageParser.claude(Data("not json".utf8), now: now))
    }

    /// One allowance covers Claude chat, Claude Code and Claude Design, and Anthropic
    /// does not break it out: `scope.surface` is null on every account seen. When it
    /// stops being null the surface has to reach the window's name by itself, because
    /// that is the only way a per-surface figure will ever appear without a new build.
    func testSurfaceScopedLimitIsNamedAfterItsSurface() throws {
        let payload = Data(#"""
        {"limits":[
          {"kind":"weekly_scoped","group":"weekly","percent":31,
           "scope":{"model":null,"surface":{"display_name":"Claude Design"}}},
          {"kind":"weekly_scoped","group":"weekly","percent":62,
           "scope":{"model":{"display_name":"Fable"},"surface":"Claude Code"}}]}
        """#.utf8)
        let windows = try UsageParser.claude(payload, now: now).windows
        XCTAssertEqual(windows.map(\.title), ["Claude Design · weekly", "Fable · Claude Code · weekly"])
        XCTAssertEqual(windows.map(\.scopeLabel), ["Claude Design", "Fable · Claude Code"])
        // Two surface-scoped limits of the same kind are two windows, not one
        // overwriting the other, so the surface has to reach the id as well.
        XCTAssertEqual(Set(windows.map(\.id)).count, 2)
    }

    /// The per-surface siblings are null on every account seen so far. Read when they
    /// are present, ignored when they are not, and never invented as zero.
    func testPerSurfaceSiblingsAreReadWhenPresentAndSkippedWhenNull() throws {
        let payload = Data(#"""
        {"limits":[{"kind":"session","group":"session","percent":10}],
         "seven_day_cowork":{"utilization":45},"seven_day_opus":null,
         "nimbus_quill":{"utilization":0}}
        """#.utf8)
        let windows = try UsageParser.claude(payload, now: now).windows
        // The session limit, plus Cowork. `seven_day_opus` is null, and `nimbus_quill`
        // is an unlabelled internal bucket that must never become a ring.
        XCTAssertEqual(windows.map(\.title), ["Current session", "Cowork · weekly"])
        XCTAssertEqual(windows.map(\.usedPercent), [10, 45])
    }
}
