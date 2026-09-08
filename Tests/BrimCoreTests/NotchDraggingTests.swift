import XCTest
import CoreGraphics
@testable import BrimCore

final class NotchDraggingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let side = CGSize(width: 64, height: 238)
    private let horizontal = CGSize(width: 260, height: 88)

    private func layout(_ dock: DockPosition? = nil, screen: CGRect? = nil) -> NotchScreenLayout {
        let frame = screen ?? self.screen
        return NotchScreenLayout(screenFrame: frame, visibleFrame: frame, reservedTop: 38, dockPosition: dock)
    }

    private func session(_ anchor: NotchAnchor, fraction: CGFloat = 0.5, pointer: CGPoint) -> NotchDragSession {
        NotchDragSession(position: NotchPosition(anchor: anchor, fraction: fraction), pointer: pointer)
    }

    private func frame(_ position: NotchPosition, _ layout: NotchScreenLayout) throws -> CGRect {
        let size = position.anchor.isHorizontal ? horizontal : side
        return try XCTUnwrap(layout.notchFrame(size: size, anchor: position.anchor, fraction: position.fraction))
    }

    // The grip can be grabbed anywhere inside the notch, so the notch must move by
    // the pointer's translation rather than centring itself under the pointer.
    func testSameEdgeDragMovesByExactlyThePointerTranslation() throws {
        let layout = layout()
        var drag = session(.right, pointer: CGPoint(x: 1400, y: 500))
        let before = try frame(NotchPosition(anchor: .right, fraction: 0.5), layout)
        let moved = try XCTUnwrap(drag.update(at: CGPoint(x: 1400, y: 560), layout: layout,
                                              sideSize: side, horizontalSize: horizontal))
        let after = try frame(moved, layout)
        XCTAssertEqual(moved.anchor, .right)
        XCTAssertEqual(after.minY - before.minY, 60, accuracy: 0.001)
        XCTAssertEqual(after.maxX, screen.maxX, "stays flush to the screen edge")
    }

    // Every update measures from the segment's baseline, so a slow drag and a single
    // jump to the same place must agree.
    func testTotalTranslationIsDriftFreeAcrossManyUpdates() throws {
        let layout = layout()
        let start = CGPoint(x: 1400, y: 300)
        var stepwise = session(.right, pointer: start)
        var direct = session(.right, pointer: start)
        for step in stride(from: CGFloat(10), through: 200, by: 10) {
            _ = stepwise.update(at: CGPoint(x: 1400, y: 300 + step), layout: layout,
                                sideSize: side, horizontalSize: horizontal)
        }
        let single = try XCTUnwrap(direct.update(at: CGPoint(x: 1400, y: 500), layout: layout,
                                                 sideSize: side, horizontalSize: horizontal))
        XCTAssertEqual(stepwise.position.anchor, single.anchor)
        XCTAssertEqual(stepwise.position.fraction, single.fraction, accuracy: 0.000_001)
    }

    func testDragContinuesOntoTheBottomEdge() throws {
        let layout = layout()
        var drag = session(.right, pointer: CGPoint(x: 1400, y: 500))
        let moved = try XCTUnwrap(drag.update(at: CGPoint(x: 700, y: 20), layout: layout,
                                              sideSize: side, horizontalSize: horizontal))
        XCTAssertEqual(moved.anchor, .bottom)
        let landed = try frame(moved, layout)
        XCTAssertEqual(landed.minY, screen.minY, "bottom placement stays flush to the screen")
        XCTAssertEqual(landed.midX, 700, accuracy: 1, "lands under the pointer on the new edge")
    }

    // Movement after a crossing is measured from the new edge, not the old one.
    func testMovementAfterCrossingIsRelativeToTheNewEdge() throws {
        let layout = layout()
        var drag = session(.right, pointer: CGPoint(x: 1400, y: 500))
        let crossed = try XCTUnwrap(drag.update(at: CGPoint(x: 700, y: 20), layout: layout,
                                                sideSize: side, horizontalSize: horizontal))
        let before = try frame(crossed, layout)
        let after = try frame(try XCTUnwrap(drag.update(at: CGPoint(x: 600, y: 20), layout: layout,
                                                        sideSize: side, horizontalSize: horizontal)), layout)
        XCTAssertEqual(after.minX - before.minX, -100, accuracy: 0.001)
    }

    // Top used to be unreachable. It is now a normal destination, and dragging near
    // the top of the screen should land there.
    func testTopIsReachableByDragging() throws {
        let layout = layout()
        for x in stride(from: CGFloat(220), through: 1220, by: 200) {
            var drag = session(.right, pointer: CGPoint(x: 1400, y: 500))
            let moved = try XCTUnwrap(drag.update(at: CGPoint(x: x, y: 895), layout: layout,
                                                  sideSize: side, horizontalSize: horizontal))
            XCTAssertEqual(moved.anchor, .top)
        }
    }

    func testDockEdgeIsSkipped() throws {
        for dock in [DockPosition.bottom, .left, .right] {
            let layout = layout(dock)
            let start: NotchAnchor = dock == .right ? .left : .right
            var drag = session(start, pointer: CGPoint(x: dock == .right ? 40 : 1400, y: 500))
            for point in [CGPoint(x: 100, y: 20), CGPoint(x: 1400, y: 20), CGPoint(x: 700, y: 400)] {
                guard let moved = drag.update(at: point, layout: layout,
                                              sideSize: side, horizontalSize: horizontal) else { continue }
                XCTAssertNotEqual(moved.anchor.rawValue, dock.rawValue, "never lands on the Dock's edge")
            }
        }
    }

    // Near a corner two edges are almost equally close; without hysteresis the notch
    // flips between them on every event.
    func testCornerHysteresisHoldsTheCurrentEdge() throws {
        let layout = layout()
        var drag = session(.right, pointer: CGPoint(x: 1400, y: 500))
        let nearlyTied = try XCTUnwrap(drag.update(at: CGPoint(x: 1400, y: 30), layout: layout,
                                                   sideSize: side, horizontalSize: horizontal))
        XCTAssertEqual(nearlyTied.anchor, .right, "a 10pt advantage is not enough to switch")
        let decisive = try XCTUnwrap(drag.update(at: CGPoint(x: 1400, y: 5), layout: layout,
                                                 sideSize: side, horizontalSize: horizontal))
        XCTAssertEqual(decisive.anchor, .bottom, "a clear advantage does switch")
    }

    func testHoldingStillDoesNotOscillate() throws {
        let layout = layout()
        var drag = session(.right, pointer: CGPoint(x: 1400, y: 500))
        let point = CGPoint(x: 1420, y: 20)
        let first = try XCTUnwrap(drag.update(at: point, layout: layout, sideSize: side, horizontalSize: horizontal))
        for _ in 0..<5 {
            let repeated = try XCTUnwrap(drag.update(at: point, layout: layout,
                                                     sideSize: side, horizontalSize: horizontal))
            XCTAssertEqual(repeated.anchor, first.anchor)
            XCTAssertEqual(repeated.fraction, first.fraction, accuracy: 0.000_001)
        }
    }

    // A fast drag can arrive as one large jump; it must clamp rather than escape.
    func testFastSingleUpdateClampsAndStaysFlush() throws {
        let layout = layout()
        var drag = session(.right, pointer: CGPoint(x: 1400, y: 500))
        let moved = try XCTUnwrap(drag.update(at: CGPoint(x: 1400, y: 5000), layout: layout,
                                              sideSize: side, horizontalSize: horizontal))
        XCTAssertEqual(moved.fraction, 1)
        let landed = try frame(moved, layout)
        XCTAssertEqual(landed.maxX, screen.maxX)
        XCTAssertLessThanOrEqual(landed.maxY, screen.maxY - 38, "stays clear of the menu bar strip")
    }

    func testWorksOnAScreenWithNegativeOrigin() throws {
        let offset = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        let layout = layout(screen: offset)
        var drag = session(.right, pointer: CGPoint(x: -40, y: -500))
        let moved = try XCTUnwrap(drag.update(at: CGPoint(x: -40, y: -440), layout: layout,
                                              sideSize: side, horizontalSize: horizontal))
        XCTAssertEqual(moved.anchor, .right)
        let landed = try XCTUnwrap(layout.notchFrame(size: side, anchor: .right, fraction: moved.fraction))
        XCTAssertEqual(landed.maxX, offset.maxX, "flush to the real screen edge, not to zero")
    }

    func testReturnsNilWhenNoEdgeCanHostTheNotch() {
        let tiny = layout(screen: CGRect(x: 0, y: 0, width: 200, height: 200))
        var drag = session(.right, pointer: CGPoint(x: 190, y: 100))
        XCTAssertNil(drag.update(at: CGPoint(x: 100, y: 100), layout: tiny,
                                 sideSize: side, horizontalSize: horizontal))
    }

    func testNonFinitePointerKeepsThePosition() throws {
        let layout = layout()
        var drag = session(.right, fraction: 0.25, pointer: CGPoint(x: 1400, y: 500))
        for point in [CGPoint(x: CGFloat.nan, y: 500), CGPoint(x: 1400, y: CGFloat.infinity)] {
            let moved = try XCTUnwrap(drag.update(at: point, layout: layout,
                                                  sideSize: side, horizontalSize: horizontal))
            XCTAssertEqual(moved.anchor, .right)
            XCTAssertEqual(moved.fraction, 0.25)
        }
    }
}
