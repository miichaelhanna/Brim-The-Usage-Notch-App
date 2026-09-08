import SwiftUI

/// The Claude Code character, used as the mark for the Claude ring.
///
/// The outline is Simple Icons' `claudecode`, published under CC0. The character
/// itself remains Anthropic's and is shown only to say which service a reading belongs
/// to, see LICENSE. Claude and Claude Code share one allowance and one ring, and of
/// the two marks this is the one people who watch those limits recognise.
///
/// It is not the app's own mark. That is the notch, in `BrandMark` and the app icon.
///
/// Body and eyes are separate subpaths on the source's 24×24 grid, filled even-odd so
/// the eyes are holes rather than a second colour. The same glyph then sits on the
/// notch's black and the dashboard's white without being told which.
enum MascotGeometry {
    static let grid: CGFloat = 24

    /// The body outline, with the eye holes removed. Only moves, lines and close.
    static let body = """
    M 21 10.5 L 24 10.5 L 24 13.5 L 21 13.5 L 21 16.5 L 19.5 16.5 L 19.5 19.5 L 18 19.5 \
    L 18 16.5 L 16.5 16.5 L 16.5 19.5 L 15 19.5 L 15 16.5 L 9 16.5 L 9 19.5 L 7.5 19.5 \
    L 7.5 16.5 L 6 16.5 L 6 19.5 L 4.5 19.5 L 4.5 16.5 L 3 16.5 L 3 13.5 L 0 13.5 \
    L 0 10.5 L 3 10.5 L 3 4.5 L 21 4.5 Z
    """

    /// The two eye slots, as the source cuts them.
    static let eyes = [CGRect(x: 6, y: 7.5, width: 1.5, height: 3),
                       CGRect(x: 16.5, y: 7.5, width: 1.5, height: 3)]

    /// Where the character actually is on its grid: the full width, but only the
    /// middle of the height.
    static let bodyBounds = CGRect(x: 0, y: 4.5, width: 24, height: 15)
}

/// The character with its eyes cut out. Fill with `FillStyle(eoFill: true)`.
///
/// Fitted by the character's own bounds, not the square it was drawn on. Fitting the
/// square left it a little over half the height of the round marks beside it, which
/// read as a smaller icon rather than a wider one.
struct ClaudeMascotGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = CGRect(x: 0, y: 0, width: MascotGeometry.grid, height: MascotGeometry.grid)
        var path = BrandMarks.path(MascotGeometry.body, in: grid, viewBox: MascotGeometry.grid)
        for eye in MascotGeometry.eyes { path.addRect(eye) }
        let body = MascotGeometry.bodyBounds
        let scale = min(rect.width / body.width, rect.height / body.height)
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                               tx: rect.midX - body.midX * scale,
                                               ty: rect.midY - body.midY * scale))
    }
}
