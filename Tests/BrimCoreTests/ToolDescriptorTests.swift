import XCTest
@testable import BrimCore

final class ToolDescriptorTests: XCTestCase {
    private func json(_ text: String) -> Any {
        try! JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    // MARK: - Key paths

    func testResolvesNestedKeysAndArrayIndices() {
        let root = json(#"{"usage":{"limits":[{"percent":24},{"percent":84}]}}"#)
        XCTAssertEqual(DescribedTool.value(at: "usage.limits[1].percent", in: root) as? Int, 84)
        XCTAssertEqual(DescribedTool.value(at: "usage.limits[0].percent", in: root) as? Int, 24)
    }

    func testMissingPathsResolveToNilRatherThanCrashing() {
        let root = json(#"{"usage":{"limits":[{"percent":24}]}}"#)
        for path in ["usage.missing", "usage.limits[9].percent", "nope.at.all",
                     "usage.limits[x].percent", "usage.limits.percent"] {
            XCTAssertNil(DescribedTool.value(at: path, in: root), path)
        }
    }

    func testIndexesIntoATopLevelArray() {
        let root = json(#"{"rows":[[1,2],[3,4]]}"#)
        XCTAssertEqual(DescribedTool.value(at: "rows[1][0]", in: root) as? Int, 3)
    }

    // MARK: - Reading

    private let descriptor = ToolDescriptor(
        id: "example", name: "Example", file: "~/.example/usage.json",
        windows: [WindowDescriptor(title: "Monthly", usedPercent: "quota.percent",
                                   resetsAt: "quota.resets_at")])

    func testReadsAPercentageAndResetTime() throws {
        let data = Data(#"{"quota":{"percent":42,"resets_at":"2026-09-20T10:00:00Z"}}"#.utf8)
        let windows = try DescribedTool.read(data, using: descriptor)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].title, "Monthly")
        XCTAssertEqual(windows[0].usedPercent, 42)
        XCTAssertNotNil(windows[0].resetsAt)
    }

    /// Most tools report a count and a cap rather than a percentage.
    func testWorksOutThePercentageFromUsedAndLimit() throws {
        let tool = ToolDescriptor(id: "counts", name: "Counts", file: "x.json",
                                  windows: [WindowDescriptor(title: "Requests",
                                                             used: "n.used", limit: "n.limit")])
        let windows = try DescribedTool.read(Data(#"{"n":{"used":30,"limit":120}}"#.utf8), using: tool)
        XCTAssertEqual(windows[0].usedPercent, 25)
    }

    /// Plenty of tools report what is left instead of what is spent.
    func testHandlesToolsThatReportWhatRemains() throws {
        let percentTool = ToolDescriptor(id: "left", name: "Left", file: "x.json",
                                         windows: [WindowDescriptor(title: "Credits",
                                                                    usedPercent: "left",
                                                                    isRemaining: true)])
        XCTAssertEqual(try DescribedTool.read(Data(#"{"left":30}"#.utf8), using: percentTool)[0].usedPercent, 70)

        let countTool = ToolDescriptor(id: "left2", name: "Left2", file: "x.json",
                                       windows: [WindowDescriptor(title: "Credits", used: "remaining",
                                                                  limit: "total", isRemaining: true)])
        XCTAssertEqual(try DescribedTool.read(Data(#"{"remaining":25,"total":100}"#.utf8),
                                              using: countTool)[0].usedPercent, 75)
    }

    func testOutOfRangeValuesAreClamped() throws {
        let data = Data(#"{"quota":{"percent":150}}"#.utf8)
        XCTAssertEqual(try DescribedTool.read(data, using: descriptor)[0].usedPercent, 100)
        let negative = Data(#"{"quota":{"percent":-20}}"#.utf8)
        XCTAssertEqual(try DescribedTool.read(negative, using: descriptor)[0].usedPercent, 0)
    }

    /// The rule the whole app runs on: absent is unknown, never zero.
    func testAMissingFieldDropsTheWindowRatherThanReportingZero() {
        let data = Data(#"{"quota":{"resets_at":"2026-09-20T10:00:00Z"}}"#.utf8)
        XCTAssertThrowsError(try DescribedTool.read(data, using: descriptor)) { error in
            XCTAssertEqual(error as? ToolDescriptorError, .noUsableWindows)
        }
    }

    func testOneBadWindowDoesNotDiscardTheGoodOnes() throws {
        let tool = ToolDescriptor(id: "mixed", name: "Mixed", file: "x.json", windows: [
            WindowDescriptor(title: "Missing", usedPercent: "nope"),
            WindowDescriptor(title: "Present", usedPercent: "here")
        ])
        let windows = try DescribedTool.read(Data(#"{"here":12}"#.utf8), using: tool)
        XCTAssertEqual(windows.map(\.title), ["Present"])
    }

    func testRejectsSomethingThatIsNotJSON() {
        XCTAssertThrowsError(try DescribedTool.read(Data("not json".utf8), using: descriptor)) { error in
            XCTAssertEqual(error as? ToolDescriptorError, .unreadableFile)
        }
    }

    func testBooleansAreNotTreatedAsNumbers() {
        let data = Data(#"{"quota":{"percent":true}}"#.utf8)
        XCTAssertThrowsError(try DescribedTool.read(data, using: descriptor))
    }

    func testDescriptorRoundTripsThroughJSON() throws {
        let described = ToolDescriptor(
            id: "cursor", name: "Cursor", detect: ["/Applications/Cursor.app"],
            file: "~/.cursor/usage.json",
            windows: [WindowDescriptor(title: "Monthly requests", used: "used", limit: "cap")],
            note: "Fast requests only.")
        let decoded = try JSONDecoder().decode(ToolDescriptor.self,
                                               from: try JSONEncoder().encode(described))
        XCTAssertEqual(decoded, described)
    }
}
