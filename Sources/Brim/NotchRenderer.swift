import AppKit
import SwiftUI
import BrimCore

/// `--render-notch <directory>`: renders the notch itself to PNGs.
///
/// The dashboard could always be looked at offscreen; the notch could not, so it was
/// being designed through geometry tests alone, which is how something ends up
/// technically correct and visually wrong. This renders every placement and both
/// states so the actual pixels can be reviewed, and re-reviewed after a change.
@MainActor
enum NotchRenderer {
    static func run(into directory: String, store: UsageStore) {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for anchor in NotchAnchor.allowedEdges {
            write(AnyView(shell(anchor, store: store, expanded: true)),
                  to: folder.appendingPathComponent("notch-\(anchor.rawValue)-expanded.png"))
            write(AnyView(shell(anchor, store: store, expanded: false)),
                  to: folder.appendingPathComponent("notch-\(anchor.rawValue)-collapsed.png"))
        }
        // The hover card is part of the notch's surface and has the same problem, and
        // is captured in the wrapper it ships in: the shadow is drawn by the card
        // itself now, so a bare `HoverDetailView` is no longer what anyone sees.
        write(AnyView(HoverCardView(content: HoverDetailView(store: store, tool: TrackedTool(.claude),
                                                            hover: { _ in }, connect: {}, openUsage: {}))),
              to: folder.appendingPathComponent("notch-card.png"))
        print("Rendered notch states into \(folder.path)")
    }

    /// Both states come off the shell the app actually ships, at the size the panel
    /// would give it. Rendering the open notch and the folded handle as two unrelated
    /// views is how they drifted apart in the first place.
    private static func shell(_ anchor: NotchAnchor, store: UsageStore, expanded: Bool) -> some View {
        let metrics = NotchMetrics(store.notchSize)
        let reveal = NotchRevealModel(isExpanded: expanded)
        let content = NotchView(store: store, reveal: reveal, placement: anchor,
                                onHover: { _, _ in }, openDashboard: {}, openUsage: { _ in },
                                onRefresh: { _ in }, onKeepOpen: {}, onHide: { _ in },
                                onSlide: { _, _ in })
        let full = NSHostingView(rootView: content).fittingSize
        let size = expanded ? full : metrics.collapsedSize(anchor)
        return NotchShellView(reveal: reveal, placement: anchor, metrics: metrics,
                              expandedSize: full, content: content)
            .frame(width: size.width, height: size.height)
    }

    /// Rendered on a mid grey rather than a transparent or black background: the notch
    /// is black, and its silhouette cannot be judged against either.
    private static func write(_ view: AnyView, to url: URL) {
        let host = NSHostingView(rootView:
            view.padding(28).background(Color(red: 0.42, green: 0.44, blue: 0.47)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
