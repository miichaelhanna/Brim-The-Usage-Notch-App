import XCTest
import CoreGraphics
@testable import BrimCore

final class NotchSlidingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let side = CGSize(width: 64, height: 238)
    private let horizontal = CGSize(width: 260, height: 88)

    private func layout(_ dock: DockPosition? = nil, screen: CGRect? = nil, visible: CGRect? = nil) -> NotchScreenLayout {
        let frame = screen ?? self.screen
        return NotchScreenLayout(screenFrame: frame, visibleFrame: visible ?? frame, reservedTop: 38, dockPosition: dock)
    }

    func testVerticalSlidesFollowGlobalYAndStayOnStartingEdge() throws {
        let layout = layout()
        for anchor in [NotchAnchor.left, .right] {
            let start = NotchPosition(anchor: anchor, fraction: 0.5)
            let original = try XCTUnwrap(layout.notchFrame(size: side, anchor: anchor, fraction: start.fraction))
            for delta: CGFloat in [-80, 60] {
                let next = try XCTUnwrap(layout.slidingPosition(from: start, translation: CGSize(width: 900, height: delta), size: side))
                let moved = try XCTUnwrap(layout.notchFrame(size: side, anchor: next.anchor, fraction: next.fraction))
                XCTAssertEqual(next.anchor, anchor)
                XCTAssertEqual(moved.minX, original.minX)
                XCTAssertEqual(moved.minY - original.minY, delta, accuracy: 0.001)
            }
        }
    }

    func testBottomSlidesFollowGlobalXAndStayFlush() throws {
        let layout = layout(.right)
        let start = NotchPosition(anchor: .bottom, fraction: 0.5)
        let original = try XCTUnwrap(layout.notchFrame(size: horizontal, anchor: .bottom))
        for delta: CGFloat in [-100, 150] {
            let next = try XCTUnwrap(layout.slidingPosition(from: start, translation: CGSize(width: delta, height: 900), size: horizontal))
            let moved = try XCTUnwrap(layout.notchFrame(size: horizontal, anchor: next.anchor, fraction: next.fraction))
            XCTAssertEqual(next.anchor, .bottom)
            XCTAssertEqual(moved.minY, screen.minY)
            XCTAssertEqual(moved.minX - original.minX, delta, accuracy: 0.001)
        }
    }

    func testPerpendicularMotionIsIgnoredIncludingNonfiniteValues() {
        let layout = layout()
        for anchor in NotchAnchor.allowedEdges {
            let start = NotchPosition(anchor: anchor, fraction: 0.37)
            for ignored: CGFloat in [-10_000, 10_000, .infinity, .nan] {
                let translation = anchor.isHorizontal ? CGSize(width: 0, height: ignored) : CGSize(width: ignored, height: 0)
                XCTAssertEqual(layout.slidingPosition(from: start, translation: translation,
                                                     size: anchor.isHorizontal ? horizontal : side), start)
            }
        }
    }

    func testClampingKeepsNotchFlushAndBelowMenuAtBothEnds() throws {
        let layout = layout()
        for anchor in NotchAnchor.allowedEdges {
            let size = anchor.isHorizontal ? horizontal : side
            let start = NotchPosition(anchor: anchor, fraction: 0.4)
            for delta: CGFloat in [-10_000, 10_000] {
                let translation = CGSize(width: delta, height: delta)
                let next = try XCTUnwrap(layout.slidingPosition(from: start, translation: translation, size: size))
                let frame = try XCTUnwrap(layout.notchFrame(size: size, anchor: next.anchor, fraction: next.fraction))
                XCTAssertEqual(next.anchor, anchor)
                XCTAssertEqual(next.fraction, delta < 0 ? 0 : 1)

                switch anchor {
                case .left, .right:
                    XCTAssertEqual(anchor == .left ? frame.minX : frame.maxX, anchor == .left ? screen.minX : screen.maxX)
                    XCTAssertEqual(delta < 0 ? frame.minY : frame.maxY, delta < 0 ? screen.minY + 8 : screen.maxY - 38 - 8)
                    XCTAssertLessThanOrEqual(frame.maxY, screen.maxY - 38 - 8)
                case .bottom:
                    XCTAssertEqual(frame.minY, screen.minY)
                    XCTAssertEqual(delta < 0 ? frame.minX : frame.maxX, delta < 0 ? screen.minX + 8 : screen.maxX - 8)
                case .top:
                    // Flush with the top of the screen, hardware notch or not.
                    XCTAssertEqual(frame.maxY, screen.maxY)
                    XCTAssertEqual(delta < 0 ? frame.minX : frame.maxX, delta < 0 ? screen.minX + 8 : screen.maxX - 8)
                }
            }
        }
    }

    func testTranslationDoesNotDependOnScreenOrigin() throws {
        for origin in [CGPoint(x: -1440, y: -400), CGPoint(x: 1440, y: 900)] {
            let frame = CGRect(origin: origin, size: screen.size)
            let offsetLayout = layout(screen: frame)
            for anchor in NotchAnchor.allowedEdges {
                let size = anchor.isHorizontal ? horizontal : side
                let start = NotchPosition(anchor: anchor, fraction: 0.5)
                let translation = CGSize(width: 75, height: -50)
                let moved = try XCTUnwrap(offsetLayout.slidingPosition(from: start, translation: translation, size: size))
                XCTAssertEqual(moved, layout().slidingPosition(from: start, translation: translation, size: size))
                let before = try XCTUnwrap(offsetLayout.notchFrame(size: size, anchor: anchor))
                let after = try XCTUnwrap(offsetLayout.notchFrame(size: size, anchor: anchor, fraction: moved.fraction))
                XCTAssertEqual(anchor.isHorizontal ? after.minX - before.minX : after.minY - before.minY,
                               anchor.isHorizontal ? 75 : -50, accuracy: 0.001)
            }
        }
    }

    func testInvalidMovementAndOversizeAreRejected() {
        for dock in [DockPosition.left, .right, .bottom] {
            let anchor = NotchAnchor(rawValue: dock.rawValue)!
            XCTAssertNil(layout(dock).slidingPosition(from: NotchPosition(anchor: anchor, fraction: 0.5),
                                                     translation: CGSize(width: 10, height: 10), size: anchor.isHorizontal ? horizontal : side))
        }
        let start = NotchPosition(anchor: .left, fraction: 0.5)
        let inset = layout(visible: CGRect(x: 80, y: 0, width: 1360, height: 862))
        XCTAssertNil(inset.slidingPosition(from: start, translation: .zero, size: side))
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(layout().slidingPosition(from: start, translation: CGSize(width: 0, height: invalid), size: side))
            XCTAssertNil(layout().slidingPosition(from: NotchPosition(anchor: .bottom, fraction: 0.5),
                                                 translation: CGSize(width: invalid, height: 0), size: horizontal))
        }
        for invalidSize in [CGSize.zero, CGSize(width: 64, height: 1000), CGSize(width: CGFloat.nan, height: 238)] {
            XCTAssertNil(layout().slidingPosition(from: start, translation: .zero, size: invalidSize))
        }
    }

    func testZeroTravelPreservesSavedFractionAndFrame() throws {
        let layout = layout()
        for anchor in NotchAnchor.allowedEdges {
            let size = anchor.isHorizontal ? CGSize(width: layout.bounds.width, height: 88) : CGSize(width: 64, height: layout.bounds.height)
            let start = NotchPosition(anchor: anchor, fraction: 0.73)
            let original = try XCTUnwrap(layout.notchFrame(size: size, anchor: anchor, fraction: start.fraction))
            let next = try XCTUnwrap(layout.slidingPosition(from: start, translation: CGSize(width: 10_000, height: -10_000), size: size))
            XCTAssertEqual(next, start)
            XCTAssertEqual(layout.notchFrame(size: size, anchor: next.anchor, fraction: next.fraction), original)
        }
    }

    func testUsingTotalTranslationDoesNotAccumulateDrift() throws {
        let layout = layout()
        let start = NotchPosition(anchor: .right, fraction: 0.3)
        _ = try XCTUnwrap(layout.slidingPosition(from: start, translation: CGSize(width: 0, height: 50), size: side))
        let next = try XCTUnwrap(layout.slidingPosition(from: start, translation: CGSize(width: 0, height: 100), size: side))
        let original = try XCTUnwrap(layout.notchFrame(size: side, anchor: .right, fraction: start.fraction))
        let moved = try XCTUnwrap(layout.notchFrame(size: side, anchor: next.anchor, fraction: next.fraction))
        XCTAssertEqual(moved.minY - original.minY, 100, accuracy: 0.001)
    }
}
