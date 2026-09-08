import XCTest
import CoreGraphics
@testable import BrimCore

final class NotchPresentationTests: XCTestCase {
    // "Keep open" exists so a card can be read, or the notch dragged, without it
    // folding away the moment the pointer leaves.
    func testKeepOpenHoldsThroughPointerExitThenReleases() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var state = NotchRevealState(collapseWhenIdle: true)
        state.reveal()
        state.keepOpen(until: start.addingTimeInterval(300))

        XCTAssertTrue(state.isPinned(at: start))
        // Two passes: the first would normally arm the deadline, the second collapse.
        XCTAssertFalse(state.updatePointer(isInside: false, now: start.addingTimeInterval(1)))
        XCTAssertFalse(state.updatePointer(isInside: false, now: start.addingTimeInterval(2)))
        XCTAssertTrue(state.isExpanded, "stays open while pinned")

        let after = start.addingTimeInterval(301)
        XCTAssertFalse(state.isPinned(at: after))
        XCTAssertFalse(state.updatePointer(isInside: false, now: after), "arms the collapse")
        XCTAssertTrue(state.updatePointer(isInside: false, now: after.addingTimeInterval(1)))
        XCTAssertFalse(state.isExpanded, "collapses once the pin expires")
    }

    func testPinCanBeReleasedEarly() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var state = NotchRevealState(collapseWhenIdle: true)
        state.reveal()
        state.keepOpen(until: start.addingTimeInterval(300))
        state.releasePin()
        XCTAssertFalse(state.isPinned(at: start))
    }

    private let now = Date(timeIntervalSince1970: 1_000)

    func testDesktopModeStaysBehindAppsAndBothModesStayBelowSystemBars() {
        XCTAssertLessThan(NotchVisibilityMode.desktopOnly.windowLevel, Int(CGWindowLevelForKey(.normalWindow)))
        XCTAssertGreaterThan(NotchVisibilityMode.desktopOnly.windowLevel, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertGreaterThan(NotchVisibilityMode.overApps.windowLevel, Int(CGWindowLevelForKey(.normalWindow)))
        for mode in NotchVisibilityMode.allCases {
            XCTAssertLessThan(mode.windowLevel, Int(CGWindowLevelForKey(.dockWindow)))
            XCTAssertLessThan(mode.windowLevel, Int(CGWindowLevelForKey(.mainMenuWindow)))
        }
        XCTAssertFalse(NotchVisibilityMode.desktopOnly.joinsFullScreenApps)
        XCTAssertTrue(NotchVisibilityMode.overApps.joinsFullScreenApps)
    }

    /// The menu bar item cannot be switched off any more. Preferences saved by builds
    /// that allowed it have to land somewhere sensible rather than resetting.
    func testSavedPresenceAlwaysKeepsTheMenuBar() {
        XCTAssertEqual(AppPresence(saved: "menuBar"), .menuBar)
        XCTAssertEqual(AppPresence(saved: "both"), .both)
        XCTAssertEqual(AppPresence(saved: "dock"), .both, "keeps its Dock icon and gains the menu bar")
        XCTAssertEqual(AppPresence(saved: "hidden"), .menuBar)
        XCTAssertEqual(AppPresence(saved: nil), .menuBar)
        XCTAssertEqual(AppPresence(saved: "nonsense"), .menuBar)
        XCTAssertFalse(AppPresence.menuBar.showsDockIcon)
        XCTAssertTrue(AppPresence.both.showsDockIcon)
    }

    func testAlwaysExpandedDoesNotCollapseWhenPointerLeaves() {
        var state = NotchRevealState(collapseWhenIdle: false)
        XCTAssertTrue(state.isExpanded)
        state.updatePointer(isInside: false, now: now)
        XCTAssertFalse(state.updatePointer(isInside: false, now: now.addingTimeInterval(60)))
        XCTAssertTrue(state.isExpanded)
    }

    func testHoverRevealsThenCollapsesAfterDelay() {
        var state = NotchRevealState(collapseWhenIdle: true)
        XCTAssertFalse(state.isExpanded)
        XCTAssertTrue(state.reveal())
        XCTAssertFalse(state.reveal())
        XCTAssertFalse(state.updatePointer(isInside: false, now: now))
        XCTAssertFalse(state.updatePointer(isInside: false, now: now.addingTimeInterval(0.2)))
        XCTAssertTrue(state.updatePointer(isInside: false, now: now.addingTimeInterval(0.4)))
        XCTAssertFalse(state.isExpanded)
        XCTAssertTrue(state.reveal())
    }

    func testMovingIntoUsageCardCancelsPendingCollapse() {
        var state = NotchRevealState(collapseWhenIdle: true)
        state.reveal()
        state.updatePointer(isInside: false, now: now)
        state.updatePointer(isInside: true, now: now.addingTimeInterval(0.2))
        XCTAssertFalse(state.updatePointer(isInside: true, now: now.addingTimeInterval(20)))
        XCTAssertTrue(state.isExpanded)
        XCTAssertFalse(state.updatePointer(isInside: false, now: now.addingTimeInterval(21)))
        XCTAssertTrue(state.updatePointer(isInside: false, now: now.addingTimeInterval(21.4)))
    }

    func testCollapsedAndExpandedFramesStayFlushWhileResizing() throws {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let layout = NotchScreenLayout(screenFrame: screen,
                                      visibleFrame: CGRect(x: -1440, y: 200, width: 1440, height: 870), reservedTop: 38)
        let safeArea = CGRect(x: screen.minX, y: layout.bounds.minY, width: screen.width, height: layout.bounds.height)
        for anchor in [NotchAnchor.right, .left] {
            let small = try XCTUnwrap(layout.notchFrame(size: NotchRevealState.collapsedSize, anchor: anchor))
            let full = try XCTUnwrap(layout.notchFrame(size: CGSize(width: 64, height: 462), anchor: anchor))
            XCTAssertTrue(full.contains(small))
            XCTAssertTrue(safeArea.contains(full))
            if anchor == .right {
                XCTAssertEqual(small.maxX, full.maxX)
                XCTAssertEqual(full.maxX, screen.maxX)
                XCTAssertEqual(small.midY, full.midY)
            } else {
                XCTAssertEqual(small.minX, full.minX)
                XCTAssertEqual(full.minX, screen.minX)
                XCTAssertEqual(small.midY, full.midY)
            }
            // Linear resizing never crosses the Dock or reserved menu strip.
            for amount in stride(from: 0.0, through: 1.0, by: 0.1) {
                let frame = CGRect(x: small.minX + (full.minX - small.minX) * amount,
                                   y: small.minY + (full.minY - small.minY) * amount,
                                   width: small.width + (full.width - small.width) * amount,
                                   height: small.height + (full.height - small.height) * amount)
                XCTAssertTrue(safeArea.contains(frame))
                XCTAssertEqual(anchor == .left ? frame.minX : frame.maxX,
                               anchor == .left ? screen.minX : screen.maxX, accuracy: 0.001)
            }
        }
    }
}
