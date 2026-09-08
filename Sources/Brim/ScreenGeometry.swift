import AppKit
import BrimCore

@MainActor
enum ScreenGeometry {
    static var target: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    /// The camera housing, when this display has one.
    ///
    /// A safe-area inset alone cannot tell a notched MacBook from a plain display with
    /// a tall menu bar, so the inset only says whether to look further. The housing's
    /// extent is the gap between the two strips of menu bar AppKit says remain usable
    /// on either side of it, measured between their edges, so it holds even if a
    /// future display puts the housing off-centre.
    static func cutout(of screen: NSScreen) -> DisplayCutout? {
        let depth = screen.safeAreaInsets.top
        guard depth > 0,
              let leftStrip = screen.auxiliaryTopLeftArea,
              let rightStrip = screen.auxiliaryTopRightArea else { return nil }
        return DisplayCutout(width: rightStrip.minX - leftStrip.maxX, depth: depth)
    }

    static var current: NotchScreenLayout? {
        guard let screen = target else { return nil }
        return NotchScreenLayout(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                 // Still the keep-out strip for the side and bottom
                                 // edges; the cutout is carried separately so the top
                                 // edge can tell the two cases apart.
                                 reservedTop: max(screen.safeAreaInsets.top, NSStatusBar.system.thickness),
                                 dockPosition: DockPositionReader.current(),
                                 cutout: cutout(of: screen))
    }
}
