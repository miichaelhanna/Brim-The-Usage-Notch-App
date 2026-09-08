import XCTest
import CoreGraphics
@testable import BrimCore

final class NotchScreenLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let edgeSize = CGSize(width: 64, height: 462)

    func testNotchAndHoverCardsAvoidDockOnEveryEdge() throws {
        let menu = CGRect(x: 0, y: 868, width: 1440, height: 32)
        let arrangements: [(CGRect, CGRect, [NotchAnchor])] = [
            (CGRect(x: 0, y: 100, width: 1440, height: 768), CGRect(x: 0, y: 0, width: 1440, height: 100), [.right, .left]),
            (CGRect(x: 100, y: 0, width: 1340, height: 868), CGRect(x: 0, y: 0, width: 100, height: 868), [.right]),
            (CGRect(x: 0, y: 0, width: 1340, height: 868), CGRect(x: 1340, y: 0, width: 100, height: 868), [.left])
        ]
        for (visible, dock, allowed) in arrangements {
            let layout = NotchScreenLayout(screenFrame: screen, visibleFrame: visible, reservedTop: 32)
            for anchor in [NotchAnchor.right, .left] {
                guard allowed.contains(anchor) else {
                    XCTAssertNil(layout.notchFrame(size: edgeSize, anchor: anchor))
                    continue
                }
                let frame = try XCTUnwrap(layout.notchFrame(size: edgeSize, anchor: anchor))
                XCTAssertFalse(frame.intersects(dock))
                XCTAssertFalse(frame.intersects(menu))
                XCTAssertTrue(visible.insetBy(dx: 0, dy: 8).contains(frame))
                XCTAssertEqual(anchor == .left ? frame.minX : frame.maxX,
                               anchor == .left ? screen.minX : screen.maxX)
                // A last-row or top-row hover can request an off-screen position.
                for origin in [CGPoint(x: -300, y: -200), CGPoint(x: 1400, y: 850)] {
                    let hover = try XCTUnwrap(layout.fittingFrame(size: CGSize(width: 300, height: 330), preferredOrigin: origin))
                    XCTAssertFalse(hover.intersects(dock))
                    XCTAssertFalse(hover.intersects(menu))
                    XCTAssertTrue(visible.insetBy(dx: 8, dy: 8).contains(hover))
                }
            }
        }
    }

    func testSidesReserveHiddenMenuAndCameraStrip() throws {
        let layout = NotchScreenLayout(screenFrame: screen, visibleFrame: screen, reservedTop: 38)
        let tallSize = CGSize(width: 64, height: screen.height - 38 - 16)
        for anchor in [NotchAnchor.right, .left] {
            let frame = try XCTUnwrap(layout.notchFrame(size: tallSize, anchor: anchor))
            XCTAssertEqual(frame.maxY, screen.maxY - 38 - 8)
            XCTAssertEqual(frame.minY, screen.minY + 8)
        }
    }

    func testDockResizeKeepsNotchFlushOnOppositeSide() throws {
        let before = NotchScreenLayout(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 0, width: 1360, height: 868), reservedTop: 32)
        let after = NotchScreenLayout(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 0, width: 1240, height: 868), reservedTop: 32)
        let oldAnchor = try XCTUnwrap(before.automaticAnchor(sideSize: edgeSize))
        let newAnchor = try XCTUnwrap(after.automaticAnchor(sideSize: edgeSize))
        XCTAssertEqual(oldAnchor, .left)
        XCTAssertEqual(newAnchor, .left)
        let oldFrame = try XCTUnwrap(before.notchFrame(size: edgeSize, anchor: oldAnchor))
        let newFrame = try XCTUnwrap(after.notchFrame(size: edgeSize, anchor: newAnchor))
        XCTAssertEqual(newFrame.minX, screen.minX)
        XCTAssertEqual(newFrame, oldFrame)
        XCTAssertNotEqual(before, after)
    }

    func testMonitorsWithNegativeAndVerticalOffsets() throws {
        for origin in [CGPoint(x: -1920, y: -400), CGPoint(x: 1440, y: 900)] {
            let display = CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
            let visible = CGRect(x: origin.x, y: origin.y, width: 1920, height: 1056)
            let layout = NotchScreenLayout(screenFrame: display, visibleFrame: visible, reservedTop: 24)
            for anchor in [NotchAnchor.right, .left] {
                let frame = try XCTUnwrap(layout.notchFrame(size: edgeSize, anchor: anchor))
                XCTAssertTrue(visible.contains(frame))
                XCTAssertLessThanOrEqual(frame.maxY, display.maxY - 32)
                XCTAssertEqual(anchor == .left ? frame.minX : frame.maxX,
                               anchor == .left ? display.minX : display.maxX)
            }
        }
    }

    func testInsufficientSpaceHidesInsteadOfCoveringSystemUI() {
        let layout = NotchScreenLayout(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 500, width: 1440, height: 368), reservedTop: 32)
        XCTAssertNil(layout.notchFrame(size: edgeSize, anchor: .right))
        XCTAssertNil(layout.notchFrame(size: edgeSize, anchor: .left))
        XCTAssertNil(layout.fittingFrame(size: CGSize(width: 2000, height: 300), preferredOrigin: .zero))
    }

    func testEmptyOrDisjointDesktopCannotProduceAWindow() {
        for visible in [CGRect.zero, CGRect(x: 2000, y: 0, width: 800, height: 600)] {
            let layout = NotchScreenLayout(screenFrame: screen, visibleFrame: visible, reservedTop: 32)
            for anchor in [NotchAnchor.right, .left] {
                XCTAssertNil(layout.notchFrame(size: edgeSize, anchor: anchor))
            }
        }
    }
}
