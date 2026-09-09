import Foundation
import CoreGraphics

public enum NotchAnchor: String, CaseIterable, Identifiable, Codable, Sendable {
    case right, left, bottom, top
    /// Order matters: automatic placement takes the first that fits, and top is
    /// last so enabling it does not silently move everyone's notch.
    public static let allowedEdges: [NotchAnchor] = [.right, .left, .bottom, .top]
    public var id: String { rawValue }
    public var isHorizontal: Bool { self == .top || self == .bottom }
    public var title: String {
        switch self { case .right: "Right edge"; case .left: "Left edge"; case .bottom: "Bottom edge"; case .top: "Top edge" }
    }
}

public struct NotchPosition: Codable, Equatable, Sendable {
    public let anchor: NotchAnchor
    /// Bottom to top on vertical edges; left to right on horizontal edges.
    public let fraction: CGFloat
    public init(anchor: NotchAnchor, fraction: CGFloat) {
        self.anchor = anchor
        self.fraction = fraction.isFinite ? max(0, min(1, fraction)) : 0.5
    }
    private enum CodingKeys: String, CodingKey { case anchor, fraction }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(anchor: try values.decode(NotchAnchor.self, forKey: .anchor),
                  fraction: try values.decode(CGFloat.self, forKey: .fraction))
    }
}

public enum DockPosition: String, Sendable { case right, left, bottom }

/// The physical notch cut into a MacBook's display.
///
/// AppKit describes a notched display by what is *usable*: a safe-area inset giving
/// how far down the housing reaches, and two strips of menu bar that survive either
/// side of it. The housing itself is never reported directly. It is whatever those
/// two strips leave uncovered. Kept as a value so the layout can be tested with a
/// made-up display instead of needing a MacBook in the test runner.
public struct DisplayCutout: Equatable, Sendable {
    /// Across the top of the screen.
    public let width: CGFloat
    /// Down from the top of the screen.
    public let depth: CGFloat
    public init?(width: CGFloat, depth: CGFloat) {
        guard width.isFinite, depth.isFinite, width > 0, depth > 0 else { return nil }
        self.width = width
        self.depth = depth
    }
}

/// AppKit screen coordinates, with the origin at bottom left.
public struct NotchScreenLayout: Equatable, Sendable {
    public let screenFrame: CGRect
    public let visibleFrame: CGRect
    public let reservedTop: CGFloat
    public let margin: CGFloat
    public let dockPosition: DockPosition?
    /// Present only on a display with a camera housing cut into it.
    public let cutout: DisplayCutout?
    public init(screenFrame: CGRect, visibleFrame: CGRect, reservedTop: CGFloat, margin: CGFloat = 8,
                dockPosition: DockPosition? = nil, cutout: DisplayCutout? = nil) {
        self.screenFrame = screenFrame; self.visibleFrame = visibleFrame
        self.reservedTop = max(0, reservedTop); self.margin = max(0, margin)
        self.dockPosition = dockPosition; self.cutout = cutout
    }

    public var bounds: CGRect {
        let visible = screenFrame.intersection(visibleFrame)
        guard !visible.isNull else { return .null }
        let top = min(visible.maxY, screenFrame.maxY - reservedTop)
        guard visible.width > margin * 2, top - visible.minY > margin * 2 else { return .null }
        return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: top - visible.minY)
            .insetBy(dx: margin, dy: margin)
    }

    private func attachmentBounds(_ anchor: NotchAnchor) -> CGRect {
        let visible = screenFrame.intersection(visibleFrame)
        guard !visible.isNull, !visible.isEmpty, !bounds.isNull else { return .null }
        var area = bounds
        // Also avoid the configured Dock edge while auto-hidden or in transit.
        switch anchor {
        case .right:
            guard dockPosition != .right, screenFrame.maxX - visible.maxX <= 0.5 else { return .null }
            area.size.width = screenFrame.maxX - area.minX
        case .left:
            guard dockPosition != .left, visible.minX - screenFrame.minX <= 0.5 else { return .null }
            area.size.width = area.maxX - screenFrame.minX; area.origin.x = screenFrame.minX
        case .bottom:
            guard dockPosition != .bottom, visible.minY - screenFrame.minY <= 0.5 else { return .null }
            area.size.height = area.maxY - screenFrame.minY; area.origin.y = screenFrame.minY
        case .top:
            // Flush with the physical top of the screen, like the hardware notch it
            // imitates: on a notched display that puts it level with the camera
            // housing, and on any other it hangs from the edge into the empty middle
            // of the menu bar. Sitting below the menu bar instead left a strip of
            // screen above it, which read as a floating black pill rather than a notch.
            guard screenFrame.maxY - area.minY > 0 else { return .null }
            area.size.height = screenFrame.maxY - area.minY
        }
        return area
    }

    public func notchFrame(size: CGSize, anchor: NotchAnchor, fraction: CGFloat = 0.5, expandedSize: CGSize? = nil) -> CGRect? {
        let area = attachmentBounds(anchor), reference = expandedSize ?? size
        guard fittingFrame(size: reference, preferredOrigin: area.origin, in: area) != nil else { return nil }
        let amount = fraction.isFinite ? max(0, min(1, fraction)) : 0.5
        let centerX = area.minX + reference.width / 2 + (area.width - reference.width) * amount
        let centerY = area.minY + reference.height / 2 + (area.height - reference.height) * amount
        let origin: CGPoint
        switch anchor {
        case .right: origin = CGPoint(x: area.maxX - size.width, y: centerY - size.height / 2)
        case .left: origin = CGPoint(x: area.minX, y: centerY - size.height / 2)
        case .bottom: origin = CGPoint(x: centerX - size.width / 2, y: area.minY)
        case .top: origin = CGPoint(x: centerX - size.width / 2, y: area.maxY - size.height)
        }
        return fittingFrame(size: size, preferredOrigin: origin, in: area)
    }

    public func automaticAnchor(sideSize: CGSize, horizontalSize: CGSize? = nil) -> NotchAnchor? {
        NotchAnchor.allowedEdges.first { anchor in
            guard let size = anchor.isHorizontal ? horizontalSize : sideSize else { return false }
            return notchFrame(size: size, anchor: anchor) != nil
        }
    }

    public func resolvedPosition(preferred: NotchPosition?, sideSize: CGSize, horizontalSize: CGSize) -> NotchPosition? {
        if let preferred, notchFrame(size: preferred.anchor.isHorizontal ? horizontalSize : sideSize,
                                     anchor: preferred.anchor, fraction: preferred.fraction) != nil { return preferred }
        return automaticAnchor(sideSize: sideSize, horizontalSize: horizontalSize).map { NotchPosition(anchor: $0, fraction: 0.5) }
    }

    /// The rectangle the notch attaches within on this edge, or nil when the
    /// edge cannot host it at all (the Dock's edge, or no room).
    public func attachmentArea(for anchor: NotchAnchor) -> CGRect? {
        let area = attachmentBounds(anchor)
        return area.isNull ? nil : area
    }

    /// The saved fraction that puts the notch's centre under `point` on `anchor`.
    /// Returns nil when the edge cannot host the notch; 0.5 when it fits exactly
    /// and there is no travel to distribute.
    public func fraction(at point: CGPoint, anchor: NotchAnchor, size: CGSize) -> CGFloat? {
        let area = attachmentBounds(anchor)
        guard fittingFrame(size: size, preferredOrigin: area.origin, in: area) != nil else { return nil }
        let horizontal = anchor.isHorizontal
        let travel = horizontal ? area.width - size.width : area.height - size.height
        guard travel.isFinite else { return nil }
        guard travel > 0 else { return 0.5 }
        let along = horizontal ? point.x : point.y
        let first = (horizontal ? area.minX : area.minY) + (horizontal ? size.width : size.height) / 2
        guard along.isFinite else { return nil }
        return max(0, min(1, (along - first) / travel))
    }

    /// Slide along the starting edge using the gesture's total translation in
    /// AppKit screen coordinates. Positive y moves upward; cross-edge motion
    /// has no effect. Pass the expanded size so a collapsed handle stays safe.
    public func slidingPosition(from position: NotchPosition, translation: CGSize, size: CGSize) -> NotchPosition? {
        let area = attachmentBounds(position.anchor)
        guard fittingFrame(size: size, preferredOrigin: area.origin, in: area) != nil else { return nil }
        let horizontal = position.anchor.isHorizontal
        let movement = horizontal ? translation.width : translation.height
        let travel = horizontal ? area.width - size.width : area.height - size.height
        guard movement.isFinite, travel.isFinite, travel >= 0 else { return nil }
        guard travel > 0 else { return position }
        let fraction = max(0, min(1, position.fraction + movement / travel))
        return NotchPosition(anchor: position.anchor, fraction: fraction)
    }

    /// How far a notch's contents must be held back from the edge it hangs on before
    /// anything drawn in them can be seen.
    ///
    /// Only the top edge of a display with a camera housing has one. The window still
    /// reaches the physical top of the screen, because that is what makes it read as
    /// part of the hardware rather than as a pill floating under the menu bar. But the
    /// housing is not a dim or clipped piece of screen, it is not screen at all, so a
    /// ring drawn under it is simply not there. The rings, the numbers, the grip and
    /// the folded handle's pill all start below it.
    public func contentInset(for anchor: NotchAnchor) -> CGFloat {
        guard anchor == .top, let cutout else { return 0 }
        return cutout.depth
    }

    /// The window a notch needs in order to show `content` on `anchor`: the contents'
    /// own size, plus whatever that edge hides. Kept here rather than at each call
    /// site, so the folded handle and the open notch cannot disagree about how much
    /// of the top of the window is unusable.
    public func windowSize(content: CGSize, anchor: NotchAnchor) -> CGSize {
        let inset = contentInset(for: anchor)
        guard inset > 0, content.height.isFinite else { return content }
        return CGSize(width: content.width, height: content.height + inset)
    }

    public func detailFrame(size: CGSize, notchFrame: CGRect, anchor: NotchAnchor, itemCenterFromTop: CGFloat) -> CGRect? {
        let origin: CGPoint
        switch anchor {
        case .right: origin = CGPoint(x: notchFrame.minX - size.width - 12, y: notchFrame.maxY - itemCenterFromTop - size.height / 2)
        case .left: origin = CGPoint(x: notchFrame.maxX + 12, y: notchFrame.maxY - itemCenterFromTop - size.height / 2)
        case .bottom: origin = CGPoint(x: notchFrame.minX + itemCenterFromTop - size.width / 2, y: notchFrame.maxY + 12)
        case .top: origin = CGPoint(x: notchFrame.minX + itemCenterFromTop - size.width / 2, y: notchFrame.minY - size.height - 12)
        }
        return fittingFrame(size: size, preferredOrigin: origin)
    }

    public func fittingFrame(size: CGSize, preferredOrigin: CGPoint) -> CGRect? {
        fittingFrame(size: size, preferredOrigin: preferredOrigin, in: bounds)
    }
    private func fittingFrame(size: CGSize, preferredOrigin: CGPoint, in area: CGRect) -> CGRect? {
        guard !area.isNull, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, size.width <= area.width, size.height <= area.height,
              preferredOrigin.x.isFinite, preferredOrigin.y.isFinite else { return nil }
        return CGRect(x: max(area.minX, min(preferredOrigin.x, area.maxX - size.width)),
                      y: max(area.minY, min(preferredOrigin.y, area.maxY - size.height)),
                      width: size.width, height: size.height)
    }
}
