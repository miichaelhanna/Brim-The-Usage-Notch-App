import Foundation
import CoreGraphics

/// How large the notch is drawn, as a multiple of the size it was designed at.
///
/// One factor rather than a set of separate dimensions. The notch was drawn to
/// proportions that hold together — the ring against the number under it, the gap at
/// each end against the grip inside it — and exposing any one of those on its own
/// would let it be broken rather than resized. Every measurement the notch takes goes
/// through `scaled`, so choosing a size grows the whole drawing at once.
public struct NotchSize: Equatable, Sendable {
    /// Smaller than 0.8 and the percentage under a ring stops being readable across a
    /// room, which is the only reason the notch is on the edge of the screen. Larger
    /// than 1.5 and two rings take most of a laptop's short edge, which is how the
    /// notch ends up in the way of the work.
    public static let range: ClosedRange<CGFloat> = 0.8...1.5
    public static let standard = NotchSize(scale: 1)
    /// The step the slider moves in, and what a saved value is snapped to. Anything
    /// finer changes nothing anyone can see and gives the notch a different pixel
    /// size on every drag.
    public static let stepPercent: CGFloat = 5

    public let scale: CGFloat

    /// Snapped and clamped on the way in, so an out-of-range or nonsense value can
    /// never reach the layout. Held in whole percent internally: two sizes chosen the
    /// same way have to compare equal, and stepping in floating point does not.
    public init(scale: CGFloat) {
        guard scale.isFinite else { self.scale = 1; return }
        let stepped = (scale * 100 / Self.stepPercent).rounded() * Self.stepPercent
        let lowest = Self.range.lowerBound * 100, highest = Self.range.upperBound * 100
        self.scale = min(max(stepped, lowest), highest) / 100
    }

    /// A value saved by an earlier launch, or nothing at all on the first one.
    public init(saved: Double?) { self.init(scale: saved.map { CGFloat($0) } ?? 1) }

    /// One of the design's measurements at this size, rounded to whole points: a
    /// column of scaled items must not accumulate a fractional drift that the notch's
    /// own frame then has to absorb.
    public func scaled(_ points: CGFloat) -> CGFloat { (points * scale).rounded() }

    /// Type is scaled but not rounded. A font is free to be 14.3pt, and rounding it
    /// makes the number under a ring jump a whole point at a time while the ring
    /// around it grows smoothly.
    public func scaledType(_ points: CGFloat) -> CGFloat { points * scale }

    /// What the control says. A percentage: "1.15" means nothing on a screen.
    public var label: String { "\(Int((scale * 100).rounded()))%" }
    public var isStandard: Bool { self == .standard }
}
