import Foundation
import CoreGraphics

/// Drives one continuous drag of the notch, both along an edge and across edges.
///
/// Same-edge motion applies the gesture's *total* translation to the segment's
/// baseline rather than accumulating per-event deltas. That is drift-free, and it
/// preserves wherever inside the notch the grip was grabbed: the first movement
/// shifts the notch by exactly as much as the pointer moved, instead of snapping
/// its centre under the pointer.
///
/// The destination edge is whichever hostable edge the pointer is nearest. That
/// makes an unavailable edge, the top or the Dock's, simply unreachable rather
/// than something the notch bounces off: a given pointer position always resolves
/// to the same edge, so holding the pointer over an excluded strip cannot make the
/// notch oscillate. Which edges are hostable is asked of the layout every update,
/// so a Dock move or display change mid-drag is picked up immediately.
public struct NotchDragSession {
    /// The position the notch should currently occupy.
    public private(set) var position: NotchPosition
    /// Start of the current edge segment. Rebased only when the edge changes, so
    /// translation is always measured from a fixed point.
    private var basePosition: NotchPosition
    private var basePointer: CGPoint

    /// How much closer a rival edge must be before it takes over. Without this a
    /// drag along a corner flips between two near-equidistant edges every event.
    public static let cornerHysteresis: CGFloat = 28

    public init(position: NotchPosition, pointer: CGPoint) {
        self.position = position
        self.basePosition = position
        self.basePointer = pointer
    }

    /// Returns the notch's new position, or nil when no edge can host it. A
    /// display change or a Dock move can leave nowhere valid mid-drag.
    public mutating func update(at point: CGPoint, layout: NotchScreenLayout,
                                sideSize: CGSize, horizontalSize: CGSize) -> NotchPosition? {
        guard point.x.isFinite, point.y.isFinite else { return position }
        func size(_ anchor: NotchAnchor) -> CGSize { anchor.isHorizontal ? horizontalSize : sideSize }

        guard let anchor = destination(for: point, layout: layout,
                                       sideSize: sideSize, horizontalSize: horizontalSize) else { return nil }

        if anchor != position.anchor {
            // Land under the pointer on the new edge, then rebase so continued
            // movement measures from here. The grab offset is deliberately not
            // carried across: the axis has usually changed, so an offset from the
            // old edge would displace the notch in a direction the user never moved.
            guard let fraction = layout.fraction(at: point, anchor: anchor, size: size(anchor)) else { return nil }
            position = NotchPosition(anchor: anchor, fraction: fraction)
            basePosition = position
            basePointer = point
            return position
        }

        let translation = CGSize(width: point.x - basePointer.x, height: point.y - basePointer.y)
        guard let moved = layout.slidingPosition(from: basePosition, translation: translation,
                                                 size: size(anchor)) else { return nil }
        position = moved
        return position
    }

    /// Nearest hostable edge, keeping the current one unless a rival is clearly closer.
    private func destination(for point: CGPoint, layout: NotchScreenLayout,
                             sideSize: CGSize, horizontalSize: CGSize) -> NotchAnchor? {
        func reach(_ anchor: NotchAnchor) -> CGFloat? {
            let size = anchor.isHorizontal ? horizontalSize : sideSize
            guard let area = layout.attachmentArea(for: anchor),
                  layout.notchFrame(size: size, anchor: anchor) != nil else { return nil }
            return Self.distance(from: point, to: anchor, in: area)
        }

        var nearest: (anchor: NotchAnchor, distance: CGFloat)?
        for anchor in NotchAnchor.allowedEdges {
            guard let distance = reach(anchor) else { continue }
            if nearest == nil || distance < nearest!.distance { nearest = (anchor, distance) }
        }
        guard let nearest else { return nil }
        guard nearest.anchor != position.anchor, let current = reach(position.anchor) else { return nearest.anchor }
        return nearest.distance + Self.cornerHysteresis < current ? nearest.anchor : position.anchor
    }

    /// Perpendicular distance from the pointer to the edge the notch attaches to.
    static func distance(from point: CGPoint, to anchor: NotchAnchor, in area: CGRect) -> CGFloat {
        switch anchor {
        case .right: abs(area.maxX - point.x)
        case .left: abs(point.x - area.minX)
        case .bottom: abs(point.y - area.minY)
        case .top: abs(area.maxY - point.y)
        }
    }
}
