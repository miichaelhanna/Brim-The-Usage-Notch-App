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
            write(AnyView(expanded(anchor, store: store)),
                  to: folder.appendingPathComponent("notch-\(anchor.rawValue)-expanded.png"))
            write(AnyView(CollapsedNotchView(placement: anchor,
                                             size: collapsedSize(anchor, store: store),
                                             metrics: NotchMetrics(store.notchSize),
                                             expand: {})),
                  to: folder.appendingPathComponent("notch-\(anchor.rawValue)-collapsed.png"))
        }
        // The hover card is part of the notch's surface and has the same problem.
        write(AnyView(HoverDetailView(store: store, tool: TrackedTool(.claude),
                                      hover: { _ in }, connect: {}, openUsage: {})),
              to: folder.appendingPathComponent("notch-card.png"))
        print("Rendered notch states into \(folder.path)")
    }

    private static func collapsedSize(_ anchor: NotchAnchor, store: UsageStore) -> CGSize {
        NotchMetrics(store.notchSize).collapsedSize(anchor)
    }

    private static func expanded(_ anchor: NotchAnchor, store: UsageStore) -> some View {
        NotchView(store: store, placement: anchor, onHover: { _, _ in }, openDashboard: {},
                  openUsage: { _ in }, onRefresh: { _ in }, onKeepOpen: {}, onHide: { _ in },
                  onSlide: { _, _ in }, animateReveal: false)
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
