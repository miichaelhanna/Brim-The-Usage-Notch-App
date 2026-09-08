import XCTest
@testable import BrimCore

final class ActivityTimelineTests: XCTestCase {
    private let utc = { () -> Calendar in
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(_ text: String) -> Date {
        guard let date = UTCTimestamp.parse(text) else {
            XCTFail("unparsable fixture \(text)"); return .distantPast
        }
        return date
    }

    /// The whole method rests on this: a long gap is time away from the desk, and
    /// counting it would turn every figure on the page into a flattering fiction.
    func testALongGapEndsARunRatherThanExtendingIt() {
        let runs = ActivityTimeline.runs(from: [
            at("2026-09-08T09:00:00Z"), at("2026-09-08T09:04:00Z"), at("2026-09-08T09:08:00Z"),
            at("2026-09-08T12:00:00Z"), at("2026-09-08T12:02:00Z")
        ], sourceID: "a")
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].duration, 480)
        XCTAssertEqual(runs[1].duration, 120)
        XCTAssertEqual(ActivityTimeline.days(runs, calendar: utc).first?.seconds, 600,
                       "the three hours in the middle are not work")
    }

    func testOutOfOrderAndDuplicateStampsAreTolerated() {
        let jumbled = ActivityTimeline.runs(from: [
            at("2026-09-08T09:04:00Z"), at("2026-09-08T09:00:00Z"),
            at("2026-09-08T09:04:00Z"), at("2026-09-08T09:06:00Z")
        ], sourceID: "a")
        XCTAssertEqual(jumbled.count, 1)
        XCTAssertEqual(jumbled[0].duration, 360, "a transcript interleaves a session with its subagents")
    }

    func testASingleStampIsASessionButNotAnHour() {
        let runs = ActivityTimeline.runs(from: [at("2026-09-08T09:00:00Z")], sourceID: "a")
        let days = ActivityTimeline.days(runs, calendar: utc)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].seconds, 0, "one instant is not a duration, and inventing one would be a lie")
        XCTAssertEqual(days[0].sessions, 1)
        XCTAssertEqual(days[0].label, "none")
    }

    /// Two agents at once is one hour of the day. A view that says two cannot be
    /// checked against a clock, which is the only check anyone will apply to it.
    func testConcurrentSessionsAreOneHourNotTwo() {
        let first = ActivityTimeline.runs(from: [at("2026-09-08T09:00:00Z"), at("2026-09-08T10:00:00Z")]
            .flatMap { stamp in stride(from: 0, through: 3600, by: 60).map { stamp.addingTimeInterval($0) } },
                                          sourceID: "a")
        let second = ActivityTimeline.runs(from: stride(from: 0, through: 3600, by: 60)
            .map { at("2026-09-08T09:30:00Z").addingTimeInterval($0) }, sourceID: "b")
        let days = ActivityTimeline.days(first + second, calendar: utc)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].seconds, 7200, "09:00 to 11:00 covered once")
        XCTAssertEqual(days[0].sessions, 2, "still two sessions")
    }

    func testANightShiftIsSplitAtMidnight() {
        let runs = [ActivityRun(start: at("2026-09-08T22:30:00Z"), end: at("2026-09-09T01:30:00Z"), sourceID: "a")]
        let days = ActivityTimeline.days(runs, calendar: utc)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].seconds, 5400)
        XCTAssertEqual(days[1].seconds, 5400)
        XCTAssertEqual(days.map(\.sessions), [1, 1])
    }

    func testNoTimestampsIsNoActivityRatherThanAnEmptyDay() {
        XCTAssertTrue(ActivityTimeline.runs(from: [], sourceID: "a").isEmpty)
        XCTAssertTrue(ActivityTimeline.days([], calendar: utc).isEmpty)
    }

    func testLabelsNeverReadAsZero() {
        XCTAssertEqual(ActivityTimeline.label(0), "none")
        XCTAssertEqual(ActivityTimeline.label(20), "under a minute")
        XCTAssertEqual(ActivityTimeline.label(38 * 60), "38m")
        XCTAssertEqual(ActivityTimeline.label(2 * 3600), "2h")
        XCTAssertEqual(ActivityTimeline.label(4 * 3600 + 12 * 60), "4h 12m")
        XCTAssertEqual(ActivityTimeline.compactLabel(0), "")
        XCTAssertEqual(ActivityTimeline.compactLabel(38 * 60), "38m")
        XCTAssertEqual(ActivityTimeline.compactLabel(4 * 3600 + 12 * 60), "4.2h")
        XCTAssertEqual(ActivityTimeline.compactLabel(11 * 3600), "11h")
    }
}

final class UTCTimestampTests: XCTestCase {
    func testReadsTheShapeTranscriptsAreWrittenIn() {
        // Claude Code and Codex both write this, to the millisecond, in UTC.
        XCTAssertEqual(UTCTimestamp.parse("2026-09-08T17:28:21.547Z"),
                       Date(timeIntervalSince1970: 1_788_888_501))
        XCTAssertEqual(UTCTimestamp.parse("1970-01-01T00:00:00Z"), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(UTCTimestamp.parse("2026-03-05T15:09:42.799Z"),
                       UTCTimestamp.parse("2026-03-05T15:09:42Z"), "the fraction is not worth keeping")
    }

    func testAgreesWithFoundationAcrossLeapYearsAndCenturies() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for text in ["2024-02-29T12:00:00Z", "2000-02-29T23:59:59Z", "1999-12-31T23:59:59Z",
                     "2026-01-01T00:00:00Z", "2038-01-19T03:14:07Z", "2100-03-01T00:00:00Z"] {
            XCTAssertEqual(UTCTimestamp.parse(text), formatter.date(from: text), text)
        }
    }

    /// Refused rather than guessed at: a stamp read as UTC when it was local would be
    /// wrong by hours, which is enough to put an evening's work on the wrong day.
    func testRefusesAnythingThatIsNotThisShape() {
        XCTAssertNil(UTCTimestamp.parse(""))
        XCTAssertNil(UTCTimestamp.parse("2026-09-08"))
        XCTAssertNil(UTCTimestamp.parse("2026-09-08 17:28:21"))
        XCTAssertNil(UTCTimestamp.parse("not a timestamp at all"))
        XCTAssertNil(UTCTimestamp.parse("2026-13-08T17:28:21Z"))
        XCTAssertNil(UTCTimestamp.parse("2026-09-08T25:28:21Z"))
        XCTAssertNil(UTCTimestamp.parse("20260908T172821Z"))
    }
}
