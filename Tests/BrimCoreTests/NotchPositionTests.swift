import XCTest
import CoreGraphics
@testable import BrimCore

final class NotchPositionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let side = CGSize(width: 64, height: 238)
    private let horizontal = CGSize(width: 260, height: 88)

    private func layout(_ dock: DockPosition? = nil) -> NotchScreenLayout {
        NotchScreenLayout(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 868),
                          reservedTop: 38, dockPosition: dock)
    }

    func testSavedChoiceReturnsAfterDockMovesAway() throws {
        let saved = NotchPosition(anchor: .left, fraction: 0.8)
        let fallback = try XCTUnwrap(layout(.left).resolvedPosition(preferred: saved, sideSize: side, horizontalSize: horizontal))
        XCTAssertEqual(fallback.anchor, .right)
        XCTAssertEqual(layout(.bottom).resolvedPosition(preferred: saved, sideSize: side, horizontalSize: horizontal), saved)
    }

    func testEveryCollapsedHandleSharesExpandedCenterAndAttachedEdge() throws {
        for anchor in NotchAnchor.allowedEdges {
            for fraction: CGFloat in [0, 0.3, 1] {
                let fullSize = anchor.isHorizontal ? horizontal : side
                let smallSize = anchor.isHorizontal ? CGSize(width: 72, height: 12) : NotchRevealState.collapsedSize
                let full = try XCTUnwrap(layout().notchFrame(size: fullSize, anchor: anchor, fraction: fraction))
                let small = try XCTUnwrap(layout().notchFrame(size: smallSize, anchor: anchor, fraction: fraction, expandedSize: fullSize))
                XCTAssertTrue(full.contains(small))
                switch anchor {
                case .left: XCTAssertEqual(small.minX, screen.minX); XCTAssertEqual(small.midY, full.midY)
                case .right: XCTAssertEqual(small.maxX, screen.maxX); XCTAssertEqual(small.midY, full.midY)
                case .bottom: XCTAssertEqual(small.minY, screen.minY); XCTAssertEqual(small.midX, full.midX)
                case .top: XCTAssertEqual(small.maxY, screen.maxY); XCTAssertEqual(small.midX, full.midX)
                }
            }
        }
    }

    // Top used to be rejected on load and rewritten to another edge. It is a real
    // placement now, so a saved one is simply honoured.
    func testSavedTopPositionIsHonoured() throws {
        let saved = try JSONDecoder().decode(NotchPosition.self, from: Data(#"{"anchor":"top","fraction":0.4}"#.utf8))
        XCTAssertEqual(saved.anchor, .top)
        for dock in [DockPosition.right, .left, .bottom] {
            XCTAssertEqual(layout(dock).resolvedPosition(preferred: saved, sideSize: side, horizontalSize: horizontal),
                           saved, "the Dock never occupies the top edge, so it cannot displace this")
        }
    }

    func testTopProducesFramesFlushWithTheScreenEdge() throws {
        XCTAssertTrue(NotchAnchor.allowedEdges.contains(.top))
        XCTAssertEqual(NotchAnchor.allowedEdges.last, .top,
                       "available, but last. Enabling top must not silently move existing notches")

        let expanded = try XCTUnwrap(layout().notchFrame(size: horizontal, anchor: .top))
        XCTAssertEqual(expanded.maxY, screen.maxY, "hangs from the edge, like the hardware notch")

        let collapsed = try XCTUnwrap(layout().notchFrame(size: CGSize(width: 72, height: 12),
                                                          anchor: .top, expandedSize: horizontal))
        XCTAssertEqual(collapsed.maxY, expanded.maxY)

        let card = try XCTUnwrap(layout().detailFrame(size: CGSize(width: 300, height: 250),
                                                      notchFrame: expanded, anchor: .top, itemCenterFromTop: 70))
        XCTAssertLessThanOrEqual(card.maxY, expanded.minY - 12, "cards open downward from a top notch")

        // Nothing fits on a display this short, top included.
        let short = NotchScreenLayout(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 850, width: 1440, height: 30),
                                      reservedTop: 38, dockPosition: .bottom)
        XCTAssertNil(short.notchFrame(size: horizontal, anchor: .top))
        XCTAssertNil(short.resolvedPosition(preferred: NotchPosition(anchor: .top, fraction: 0.5),
                                            sideSize: side, horizontalSize: horizontal))
    }

    /// The top notch touches the physical top of the screen on every display. On a
    /// notched Mac that is level with the camera housing, so it can hide inside it; on
    /// any other it hangs from the edge, into the empty middle of the menu bar. It used
    /// to sit below the menu bar on plain displays, which left a strip of screen above
    /// it and read as a floating pill rather than a notch.
    func testTopIsFlushWithTheScreenWithOrWithoutAHardwareNotch() throws {
        let notched = NotchScreenLayout(screenFrame: screen, visibleFrame: screen, reservedTop: 38,
                                        dockPosition: .bottom,
                                        cutout: DisplayCutout(width: 200, depth: 38))
        let frame = try XCTUnwrap(notched.notchFrame(size: horizontal, anchor: .top))
        XCTAssertEqual(frame.maxY, screen.maxY, "level with the camera housing")

        let plain = try XCTUnwrap(layout(.bottom).notchFrame(size: horizontal, anchor: .top))
        XCTAssertEqual(plain.maxY, screen.maxY, "and still flush when there is no hardware notch")

        // A hidden or auto-hiding menu bar changes nothing: the edge is the edge.
        let noMenuBar = NotchScreenLayout(screenFrame: screen, visibleFrame: screen, reservedTop: 0, dockPosition: .bottom)
        XCTAssertEqual(try XCTUnwrap(noMenuBar.notchFrame(size: horizontal, anchor: .top)).maxY, screen.maxY)

        // The side edges still keep out of the menu bar strip.
        let side = try XCTUnwrap(layout(.bottom).notchFrame(size: self.side, anchor: .right, fraction: 1))
        XCTAssertLessThanOrEqual(side.maxY, screen.maxY - 38 - 8)
    }

    func testDisplayCutoutRejectsImpossibleDimensions() {
        XCTAssertNil(DisplayCutout(width: 0, depth: 38))
        XCTAssertNil(DisplayCutout(width: 200, depth: 0))
        XCTAssertNil(DisplayCutout(width: .nan, depth: 38))
    }

    func testPositionRoundTripsAndRejectsInvalidFractions() throws {
        let original = NotchPosition(anchor: .bottom, fraction: 0.72)
        XCTAssertEqual(try JSONDecoder().decode(NotchPosition.self, from: JSONEncoder().encode(original)), original)
        XCTAssertEqual(NotchPosition(anchor: .left, fraction: .nan).fraction, 0.5)
        XCTAssertEqual(NotchPosition(anchor: .left, fraction: -5).fraction, 0)
        let decoded = try JSONDecoder().decode(NotchPosition.self, from: Data(#"{"anchor":"right","fraction":10}"#.utf8))
        XCTAssertEqual(decoded.fraction, 1)
    }
}
