import XCTest
@testable import BrimCore

final class ClaudeUsageCacheTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    /// Shaped exactly like the real file, including the model-scoped entry the
    /// sibling named keys leave null.
    private let real = """
    {"cachedUsageUtilization": {
      "accountUuid": "abc-123",
      "fetchedAtMs": 1787363819027,
      "utilization": {
        "five_hour": {"utilization": 24, "resets_at": "2026-08-22T06:20:00.098548+00:00"},
        "seven_day": {"utilization": 50, "resets_at": "2026-08-23T19:00:00.098571+00:00"},
        "seven_day_opus": null,
        "limits": [
          {"kind":"session","group":"session","percent":24,"severity":"normal",
           "resets_at":"2026-08-22T06:20:00.098548+00:00","scope":null,"is_active":false},
          {"kind":"weekly_all","group":"weekly","percent":50,"severity":"normal",
           "resets_at":"2026-08-23T19:00:00.098571+00:00","scope":null,"is_active":false},
          {"kind":"weekly_scoped","group":"weekly","percent":84,"severity":"warning",
           "resets_at":"2026-08-23T19:00:00.098810+00:00",
           "scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":true}
        ]
      }
    }}
    """

    func testReadsLimitsIncludingSeverityScopeAndActiveWindow() throws {
        let reading = try XCTUnwrap(try ClaudeUsageCache.read(data(real)))
        XCTAssertEqual(reading.accountUUID, "abc-123")
        XCTAssertEqual(reading.snapshot.provider, .claudeCode)
        XCTAssertEqual(reading.snapshot.source, .claudeCache)
        XCTAssertEqual(reading.snapshot.windows.count, 3)

        let scoped = try XCTUnwrap(reading.snapshot.windows.first { $0.isActive })
        XCTAssertEqual(scoped.title, "Fable · weekly", "model-scoped limits are named by their model")
        XCTAssertEqual(scoped.scopeLabel, "Fable")
        XCTAssertEqual(scoped.usedPercent, 84)
        XCTAssertEqual(scoped.severity, .warning)
        XCTAssertEqual(scoped.durationMinutes, 10080)

        let session = try XCTUnwrap(reading.snapshot.windows.first { $0.id == "session" })
        XCTAssertEqual(session.title, "Current session")
        XCTAssertEqual(session.severity, .normal)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.durationMinutes, 300)
    }

    /// The whole point of carrying fetchedAtMs: this cache is often days old, and the
    /// age has to survive into the snapshot so it can be shown.
    func testFetchedAtBecomesTheSnapshotTimestamp() throws {
        let reading = try XCTUnwrap(try ClaudeUsageCache.read(data(real)))
        XCTAssertEqual(reading.snapshot.updatedAt.timeIntervalSince1970, 1_787_363_819.027, accuracy: 0.01)
        XCTAssertTrue(reading.snapshot.isStale(at: reading.snapshot.updatedAt.addingTimeInterval(3600)))
    }

    func testParsesFractionalSecondISO8601ResetTimes() throws {
        let reading = try XCTUnwrap(try ClaudeUsageCache.read(data(real)))
        let session = try XCTUnwrap(reading.snapshot.windows.first { $0.id == "session" })
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(session.resetsAt, expected.date(from: "2026-08-22T06:20:00.098548+00:00"))
    }

    func testMissingPercentIsDroppedNotTreatedAsZero() throws {
        let json = """
        {"cachedUsageUtilization": {"fetchedAtMs": 1787363819027, "utilization": {"limits": [
          {"kind":"session","group":"session","percent":null,"is_active":false},
          {"kind":"weekly_all","group":"weekly","percent":50,"is_active":true}
        ]}}}
        """
        let reading = try XCTUnwrap(try ClaudeUsageCache.read(data(json)))
        XCTAssertEqual(reading.snapshot.windows.count, 1)
        XCTAssertEqual(reading.snapshot.windows.first?.id, "weekly_all")
        XCTAssertFalse(reading.snapshot.windows.contains { $0.usedPercent == 0 })
    }

    func testFallsBackToNamedKeysWhenLimitsAreAbsent() throws {
        let json = """
        {"cachedUsageUtilization": {"fetchedAtMs": 1787363819027, "utilization": {
          "five_hour": {"utilization": 24, "resets_at": "2026-08-22T06:20:00.098548+00:00"},
          "seven_day": {"utilization": 50, "resets_at": null}
        }}}
        """
        let reading = try XCTUnwrap(try ClaudeUsageCache.read(data(json)))
        XCTAssertEqual(reading.snapshot.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(reading.snapshot.windows.first?.usedPercent, 24)
        XCTAssertNil(reading.snapshot.windows.last?.resetsAt)
    }

    func testNoUsageBlockReturnsNilRatherThanClearingQuotas() throws {
        XCTAssertNil(try ClaudeUsageCache.read(data(#"{"someOtherKey": 1}"#)))
    }

    /// An empty block is a real statement, since the account has no limits to report,
    /// and must not be confused with the block being absent.
    func testEmptyLimitsClearsQuotas() throws {
        let json = #"{"cachedUsageUtilization": {"fetchedAtMs": 1787363819027, "utilization": {"limits": []}}}"#
        let reading = try XCTUnwrap(try ClaudeUsageCache.read(data(json)))
        XCTAssertTrue(reading.snapshot.windows.isEmpty)
    }

    func testRejectsUnusableDocuments() {
        XCTAssertThrowsError(try ClaudeUsageCache.read(data("not json")))
        XCTAssertThrowsError(try ClaudeUsageCache.read(data(#"{"cachedUsageUtilization": {"utilization": {}}}"#)),
                             "a reading with no fetch time cannot be aged, so it is unusable")
    }

    func testUnknownLimitKindStillReadable() throws {
        let json = """
        {"cachedUsageUtilization": {"fetchedAtMs": 1787363819027, "utilization": {"limits": [
          {"kind":"monthly_extra","group":"monthly","percent":12,"severity":"critical","is_active":false}
        ]}}}
        """
        let reading = try XCTUnwrap(try ClaudeUsageCache.read(data(json)))
        let window = try XCTUnwrap(reading.snapshot.windows.first)
        XCTAssertEqual(window.title, "Monthly Extra")
        XCTAssertEqual(window.severity, .critical)
        XCTAssertNil(window.durationMinutes)
    }
}
