import XCTest
import CoreGraphics
@testable import BrimCore

final class AutomaticPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let side = CGSize(width: 64, height: 462)

    private func layout(_ dock: DockPosition?, visible: CGRect? = nil) -> NotchScreenLayout {
        NotchScreenLayout(screenFrame: screen,
                          visibleFrame: visible ?? CGRect(x: 0, y: 0, width: 1440, height: 870),
                          reservedTop: 30, dockPosition: dock)
    }

    func testRightDockSelectsLeftEvenWhileAutoHidden() throws {
        let layout = layout(.right)
        let anchor = try XCTUnwrap(layout.automaticAnchor(sideSize: side))
        XCTAssertEqual(anchor, .left)
        XCTAssertEqual(try XCTUnwrap(layout.notchFrame(size: side, anchor: anchor)).minX, screen.minX)
    }

    func testLeftAndBottomDocksPreferRight() {
        for dock in [DockPosition.left, .bottom] {
            XCTAssertEqual(layout(dock).automaticAnchor(sideSize: side), .right)
        }
    }

    func testVisibleDockInsetsAreRespectedWithoutPreferenceData() {
        let right = layout(nil, visible: CGRect(x: 0, y: 0, width: 1360, height: 870))
        let left = layout(nil, visible: CGRect(x: 80, y: 0, width: 1360, height: 870))
        XCTAssertEqual(right.automaticAnchor(sideSize: side), .left)
        XCTAssertEqual(left.automaticAnchor(sideSize: side), .right)
    }

    func testHiddenDockMoveInvalidatesLayoutWithoutChangingVisibleFrame() {
        let before = layout(.right), after = layout(.left)
        XCTAssertEqual(before.visibleFrame, after.visibleFrame)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(before.automaticAnchor(sideSize: side), .left)
        XCTAssertEqual(after.automaticAnchor(sideSize: side), .right)
    }

    func testDockMoveAvoidsBothOldAndNewSidesDuringTransition() {
        let moving = layout(.right, visible: CGRect(x: 80, y: 0, width: 1360, height: 870))
        XCTAssertNil(moving.automaticAnchor(sideSize: side))
    }

    func testInsufficientVerticalSpaceHidesEvenWhenHandleFits() {
        let smallDesktop = layout(.bottom, visible: CGRect(x: 0, y: 550, width: 1440, height: 320))
        XCTAssertNotNil(smallDesktop.notchFrame(size: NotchRevealState.collapsedSize, anchor: .right))
        XCTAssertNil(smallDesktop.automaticAnchor(sideSize: side))
        XCTAssertEqual(smallDesktop.automaticAnchor(sideSize: CGSize(width: 64, height: 200)), .right)
    }

    func testNoAvailableEdgeHidesInsteadOfSharingDockSide() {
        let tiny = layout(.right, visible: CGRect(x: 0, y: 850, width: 100, height: 20))
        XCTAssertNil(tiny.automaticAnchor(sideSize: side))
    }

    func testCardsOpenInwardOnAllowedEdges() throws {
        let layout = layout(nil)
        let cardSize = CGSize(width: 300, height: 250)
        for anchor in NotchAnchor.allowedEdges {
            let notch = try XCTUnwrap(layout.notchFrame(size: anchor.isHorizontal ? CGSize(width: 400, height: 88) : side, anchor: anchor))
            let card = try XCTUnwrap(layout.detailFrame(size: cardSize, notchFrame: notch, anchor: anchor, itemCenterFromTop: 70))
            XCTAssertTrue(layout.bounds.contains(card))
            switch anchor {
            case .left: XCTAssertGreaterThanOrEqual(card.minX, notch.maxX + 12)
            case .right: XCTAssertLessThanOrEqual(card.maxX, notch.minX - 12)
            case .top: XCTAssertLessThanOrEqual(card.maxY, notch.minY - 12)
            case .bottom: XCTAssertGreaterThanOrEqual(card.minY, notch.maxY + 12)
            }
        }
    }
}
