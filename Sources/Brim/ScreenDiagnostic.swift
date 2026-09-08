import AppKit
import BrimCore

/// `--diagnose-screen`: what the app sees about your displays.
///
/// Placement bugs are almost always geometry the app read differently from how the
/// screen actually is, and that is invisible from a screenshot. This output is safe to
/// paste into an issue. It contains no personal data.
@MainActor
enum ScreenDiagnostic {
    static func run() {
        print("Dock: \(DockPositionReader.current().rawValue)")
        print("Menu bar thickness: \(NSStatusBar.system.thickness)")
        for (index, screen) in NSScreen.screens.enumerated() {
            let isTarget = screen === ScreenGeometry.target
            print("\nScreen \(index)\(isTarget ? " (target)" : "")")
            print("  frame:       \(screen.frame)")
            print("  visible:     \(screen.visibleFrame)")
            print("  safe top:    \(screen.safeAreaInsets.top)")
            if let notch = ScreenGeometry.cutout(of: screen) {
                print("  hardware notch: \(notch.width) x \(notch.depth)")
            } else {
                print("  hardware notch: none")
            }
        }
        guard let layout = ScreenGeometry.current else {
            print("\nNo usable layout.")
            return
        }
        let side = CGSize(width: 64, height: 238), horizontal = CGSize(width: 260, height: 88)
        print("\nPlacements")
        for anchor in NotchAnchor.allowedEdges {
            let size = anchor.isHorizontal ? horizontal : side
            if let frame = layout.notchFrame(size: size, anchor: anchor) {
                print("  \(anchor.rawValue): \(frame)")
            } else {
                print("  \(anchor.rawValue): unavailable")
            }
        }
    }
}
