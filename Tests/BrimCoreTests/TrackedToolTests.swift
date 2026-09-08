import XCTest
@testable import BrimCore

final class TrackedToolTests: XCTestCase {
    private func descriptor(id: String = "example", name: String = "Example",
                            file: String = "~/.example/usage.json",
                            detect: [String]? = nil,
                            windows: [WindowDescriptor] = [WindowDescriptor(title: "Monthly", usedPercent: "p")])
        -> ToolDescriptor {
        ToolDescriptor(id: id, name: name, detect: detect, file: file, windows: windows)
    }

    // MARK: - Identity

    /// A described tool's id must not be able to collide with a provider's, because
    /// both are used as the same storage key.
    func testDescribedIdentitiesAreNamespacedAwayFromProviders() {
        let clash = TrackedTool(descriptor(id: "claude", name: "Not Claude"))
        XCTAssertNotEqual(clash.id, TrackedTool(.claude).id)
        XCTAssertEqual(clash.descriptorID, "claude")
        XCTAssertNil(TrackedTool(.claude).descriptorID)
    }

    func testProviderIdentitiesKeepTheirRawValues() {
        // Saved preferences are keyed by these; changing one would silently reset it.
        XCTAssertEqual(TrackedTool(.claudeCode).id, "claudeCode")
        XCTAssertEqual(TrackedTool(.chatgpt).name, "ChatGPT")
        // The figure is the Work allowance; the ring has to say so somewhere.
        XCTAssertNotNil(TrackedTool(.chatgpt).scopeNote)
        XCTAssertNotNil(TrackedTool(.claude).scopeNote)
    }

    func testMonogramTakesInitialsAndFallsBackToLetters() {
        XCTAssertEqual(TrackedTool(descriptor(name: "Open Router")).monogram, "OR")
        XCTAssertEqual(TrackedTool(descriptor(name: "cursor")).monogram, "CU")
        XCTAssertEqual(TrackedTool(descriptor(name: "v0")).monogram, "V0")
        // No crash and no blank ring for a name the app cannot abbreviate.
        XCTAssertEqual(TrackedTool(descriptor(name: "·")).monogram, "")
    }

    // MARK: - Validation

    func testAcceptsAUsableDescription() {
        XCTAssertEqual(descriptor().problems(), [])
        XCTAssertEqual(descriptor(windows: [WindowDescriptor(title: "N", used: "a", limit: "b")]).problems(), [])
    }

    func testRejectsDescriptionsThatCannotProduceANumber() {
        let noPaths = descriptor(windows: [WindowDescriptor(title: "Monthly", used: "a")])
        XCTAssertEqual(noPaths.problems().count, 1)
        XCTAssertTrue(noPaths.problems()[0].contains("Monthly"), "the message has to name the window")
        XCTAssertFalse(descriptor(windows: []).problems().isEmpty)
    }

    func testRejectsIdentifiersThatWouldNotWorkAsStorageKeys() {
        for bad in ["", "Has Space", "UPPER", "punct!", String(repeating: "a", count: 41)] {
            XCTAssertFalse(descriptor(id: bad).problems().isEmpty, bad)
        }
        XCTAssertEqual(descriptor(id: "open-router_2").problems(), [])
    }

    func testRejectsAnEmptyNameOrFile() {
        XCTAssertFalse(descriptor(name: " ").problems().isEmpty)
        XCTAssertFalse(descriptor(file: "").problems().isEmpty)
    }

    // MARK: - Detection

    func testWithoutDetectPathsATooolIsAlwaysShown() {
        XCTAssertTrue(descriptor().isInstalled())
        XCTAssertTrue(descriptor(detect: []).isInstalled())
    }

    func testDetectPathsExpandTildeAndDecideVisibility() {
        XCTAssertTrue(descriptor(detect: ["~", "/nope"]).isInstalled())
        XCTAssertFalse(descriptor(detect: ["/nope/at/all"]).isInstalled())
    }

    func testResolvedFileExpandsTilde() {
        XCTAssertFalse(descriptor().resolvedFile.path.contains("~"))
        XCTAssertTrue(descriptor().resolvedFile.path.hasSuffix("/.example/usage.json"))
    }

    // MARK: - Readings

    func testStalenessFollowsTheSourceRatherThanOneFixedRule() {
        let now = Date()
        let live = ToolReading(windows: [], sourceLabel: "Live", updatedAt: now, freshFor: 600)
        XCTAssertFalse(live.isStale(at: now.addingTimeInterval(599)))
        XCTAssertTrue(live.isStale(at: now.addingTimeInterval(601)))
    }

    func testHeadlineFollowsTheLimitThatIsActuallyBiting() {
        let now = Date()
        let session = UsageWindow(id: "s", title: "Session", usedPercent: 10)
        let weekly = UsageWindow(id: "w", title: "Weekly", usedPercent: 90, isActive: true)
        let reading = ToolReading(windows: [session, weekly], sourceLabel: "x", updatedAt: now)
        XCTAssertEqual(reading.headline(at: now)?.id, "w")
        XCTAssertEqual(reading.primary(at: now)?.id, "s")
    }

    func testExpiredWindowsAreNotOfferedAsAReading() {
        let now = Date()
        let expired = UsageWindow(id: "s", title: "Session", usedPercent: 10,
                                  resetsAt: now.addingTimeInterval(-60), isActive: true)
        let reading = ToolReading(windows: [expired], sourceLabel: "x", updatedAt: now)
        XCTAssertNil(reading.headline(at: now))
    }

    func testASnapshotBecomesAReadingWithoutLosingItsTimestamp() {
        let taken = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(provider: .codex,
                                     windows: [UsageWindow(id: "p", title: "Session", usedPercent: 40)],
                                     source: .codex, updatedAt: taken)
        let reading = ToolReading(snapshot)
        XCTAssertEqual(reading.updatedAt, taken)
        XCTAssertEqual(reading.sourceLabel, UsageSource.codex.label)
        XCTAssertEqual(reading.windows.count, 1)
    }
}
