import AppKit
import SwiftUI
import BrimCore

/// The notch has to stay small. It lives on a screen edge permanently, so every
/// point it takes is one the user does not get back. Five providers at the old
/// figures made it roughly 900pt tall, most of a laptop screen.
///
/// Small, but not cramped. With one ring per allowance there are two rings rather than
/// four, and the first cut at these figures, 54pt wide with 7pt between rings, read as
/// crowded, so the rings were given room to breathe instead.
struct NotchMetrics {
    /// The size every figure below is written at. `NotchSize` multiplies them, so the
    /// one control in Settings moves all of them together and the drawing is resized
    /// rather than rearranged.
    let size: NotchSize
    init(_ size: NotchSize = .standard) { self.size = size }
    private func scaled(_ points: CGFloat) -> CGFloat { size.scaled(points) }

    var edgeWidth: CGFloat { scaled(66) }
    var edgeItemHeight: CGFloat { scaled(56) }
    var edgeItemWidth: CGFloat { scaled(56) }
    /// A single ring on a top or bottom edge puts its number beside it rather than
    /// under it: a bar has width to spend and no height to waste. Stacking is for a
    /// column of rings, and for the side edges, which have neither.
    var edgeRowItemWidth: CGFloat { ring + rowNumberSpacing + rowNumberWidth }
    var edgeRowItemHeight: CGFloat { scaled(40) }
    /// Wide enough for the widest reading, and no wider. The number is centred in it
    /// rather than aligned to one end, so the gap either side of it stays equal
    /// whether it says 8% or 100%.
    var rowNumberWidth: CGFloat { scaled(42) }
    var rowNumberSpacing: CGFloat { scaled(8) }
    var edgeSpacing: CGFloat { scaled(12) }
    var ring: CGFloat { scaled(36) }
    /// Between a ring and the number under it.
    var stackSpacing: CGFloat { scaled(5) }
    /// The button that opens the app. Its circle is its frame, so the gap it leaves
    /// at that end of the notch is the gap you actually see.
    var openButton: CGFloat { scaled(22) }

    var gripThickness: CGFloat { scaled(20) }
    /// Across the strip: the grip's other dimension, and its hit area.
    var gripBreadth: CGFloat { scaled(34) }

    /// The visible gap between the end of the notch and the first thing drawn in it.
    ///
    /// Measured to the ink rather than to a frame. The grip's dots sit inside their
    /// view with slack around them, so the padding on that end is reduced by exactly
    /// that slack and both ends read as the same distance, which is the only thing
    /// anyone can see. It also has to clear the shape's flared shoulder, which eats
    /// roughly the first 33pt: a grip flush to the end lands half outside the
    /// silhouette and cannot be grabbed.
    var endGap: CGFloat { scaled(26) }
    /// Derived, not typed twice. These drifted apart once already.
    var leadingPadding: CGFloat { endGap - (gripThickness - scaled(NotchGripView.inkAlongStrip)) / 2 }
    var trailingPadding: CGFloat { endGap }
    /// Across the strip, on a top or bottom edge. A side edge has a fixed width
    /// instead, and centres its items in it.
    var crossPadding: CGFloat { scaled(12) }

    /// Type. Scaled but not rounded, so the number grows as smoothly as the ring
    /// around it.
    var numberType: CGFloat { size.scaledType(13) }
    var openGlyphType: CGFloat { size.scaledType(11) }
    /// The collapsed handle, and the pill drawn on it. It is the only thing on screen
    /// while the notch is folded away, so it follows the same size as the rest.
    func collapsedSize(_ anchor: NotchAnchor) -> CGSize {
        let base = NotchRevealState.collapsedSize
        let thickness = scaled(base.width), length = scaled(base.height)
        return anchor.isHorizontal ? CGSize(width: length, height: thickness)
                                   : CGSize(width: thickness, height: length)
    }
    var collapsedCapDepth: CGFloat { scaled(24) }
    var collapsedPill: CGSize { CGSize(width: scaled(26), height: scaled(2)) }

    /// Where the rings begin, measured from the leading end of the notch: past the
    /// grip and the gap after it. Derived so the hover card and the layout cannot
    /// disagree about where an item is.
    var contentLeadingInset: CGFloat { leadingPadding + gripThickness + edgeSpacing }

    func laysSideBySide(anchor: NotchAnchor, toolCount: Int) -> Bool {
        anchor.isHorizontal && toolCount == 1
    }
    func itemSize(anchor: NotchAnchor, toolCount: Int) -> CGSize {
        laysSideBySide(anchor: anchor, toolCount: toolCount)
            ? CGSize(width: edgeRowItemWidth, height: edgeRowItemHeight)
            : CGSize(width: edgeItemWidth, height: edgeItemHeight)
    }
    /// The item's extent along the edge it is laid out on.
    func itemLength(anchor: NotchAnchor, toolCount: Int) -> CGFloat {
        let size = itemSize(anchor: anchor, toolCount: toolCount)
        return anchor.isHorizontal ? size.width : size.height
    }
    /// On a top or bottom edge a stacked item is a ring with its number under it, so
    /// the middle of the item sits below the middle of the ring. The grip and the open
    /// button belong on the ring's line, since centred on the item they read as sagging.
    /// A side edge centres across its width, where the ring already is, and a single
    /// ring on a bar has its number beside it, so neither needs this.
    func ringLineOffset(anchor: NotchAnchor, toolCount: Int) -> CGFloat {
        guard anchor.isHorizontal, !laysSideBySide(anchor: anchor, toolCount: toolCount) else { return 0 }
        return (edgeItemHeight - ring) / 2
    }

    /// The centre of one item, from the leading end of the notch.
    func itemCenter(index: Int, anchor: NotchAnchor, toolCount: Int) -> CGFloat {
        let length = itemLength(anchor: anchor, toolCount: toolCount)
        return contentLeadingInset + length / 2 + CGFloat(index) * (length + edgeSpacing)
    }
}

struct EdgeNotchShape: Shape {
    var placement: NotchAnchor = .right
    var endCapDepth: CGFloat?
    func path(in rect: CGRect) -> Path {
        let w = placement.isHorizontal ? rect.height : rect.width
        let h = placement.isHorizontal ? rect.width : rect.height
        let scale = w / 92
        // Keep the curved ends visible when the notch becomes a thin handle.
        // Scaling both axes from its width would flatten them into tiny corners.
        let cap = min(h / 2, endCapDepth ?? 56 * scale)
        let shoulder = cap * 24 / 56
        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        p.addCurve(to: CGPoint(x: 31 * scale, y: shoulder), control1: CGPoint(x: w, y: shoulder), control2: CGPoint(x: 58 * scale, y: shoulder))
        p.addQuadCurve(to: CGPoint(x: 0, y: cap), control: CGPoint(x: 0, y: shoulder))
        p.addLine(to: CGPoint(x: 0, y: h - cap))
        p.addQuadCurve(to: CGPoint(x: 31 * scale, y: h - shoulder), control: CGPoint(x: 0, y: h - shoulder))
        p.addCurve(to: CGPoint(x: w, y: h), control1: CGPoint(x: 58 * scale, y: h - shoulder), control2: CGPoint(x: w, y: h - shoulder))
        p.closeSubpath()
        switch placement {
        case .right: return p
        case .left: return p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
        case .top: return p.applying(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
        case .bottom: return p.applying(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
        }
    }
}

struct NotchView: View {
    @ObservedObject var store: UsageStore
    let placement: NotchAnchor
    var onHover: (TrackedTool, Bool) -> Void
    var openDashboard: () -> Void
    var openUsage: (TrackedTool) -> Void
    var onRefresh: (TrackedTool) -> Void
    var onKeepOpen: () -> Void
    var onHide: (TrackedTool) -> Void
    var onSlide: (CGPoint, NotchSlidePhase) -> Void
    /// Off for offscreen rendering: `onAppear` never fires for a view that is never
    /// in a window, so the reveal would never complete and the capture would be blank.
    var animateReveal = true
    @State private var revealed = false
    @State private var openHovered = false
    /// Read from the store rather than passed in, so changing the size in Settings
    /// redraws the notch the same way changing anything else on it does.
    private var metrics: NotchMetrics { NotchMetrics(store.notchSize) }
    /// Honoured rather than assumed: an edge notch that pops open is exactly the kind
    /// of motion people turn this off to avoid.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        let metrics = self.metrics
        let sideBySide = metrics.laysSideBySide(anchor: placement, toolCount: store.activeTools.count)
        let ringLine = metrics.ringLineOffset(anchor: placement, toolCount: store.activeTools.count)
        let layout = placement.isHorizontal ? AnyLayout(HStackLayout(spacing: metrics.edgeSpacing)) : AnyLayout(VStackLayout(spacing: metrics.edgeSpacing))
        layout {
            // The grip is a member of the stack rather than an overlay sitting on
            // padding reserved for it. As an overlay only the leading end held a
            // grip, while both ends reserved room for one, so the notch had a wide
            // empty margin at one end and a tight one at the other.
            NotchPositionControl(onDrag: onSlide, scale: metrics.size.scale)
                .frame(width: placement.isHorizontal ? metrics.gripThickness : metrics.gripBreadth,
                       height: placement.isHorizontal ? metrics.gripBreadth : metrics.gripThickness)
                .offset(y: -ringLine)
            // The rings arrive in sequence rather than all at once. The stagger is
            // small, a few frames apart, because the notch opens on hover and a
            // slower one would still be animating when the pointer arrives.
            ForEach(Array(store.activeTools.enumerated()), id: \.element) { index, tool in
                item(tool, sideBySide: sideBySide)
                    .opacity(revealed || !animateReveal ? 1 : 0)
                    .scaleEffect(revealed || !animateReveal ? 1 : 0.82)
                    .animation(reduceMotion ? nil
                               : .spring(response: 0.32, dampingFraction: 0.8)
                                   .delay(Double(index) * 0.035),
                               value: revealed)
            }
            openButton.offset(y: -ringLine)
        }.padding(.leading, placement.isHorizontal ? metrics.leadingPadding : 0)
            .padding(.trailing, placement.isHorizontal ? metrics.trailingPadding : 0)
            .padding(.top, placement.isHorizontal ? metrics.crossPadding : metrics.leadingPadding)
            .padding(.bottom, placement.isHorizontal ? metrics.crossPadding : metrics.trailingPadding)
            .frame(width: placement.isHorizontal ? nil : metrics.edgeWidth)
            .background(EdgeNotchShape(placement: placement).fill(.black))
            .foregroundStyle(.white).preferredColorScheme(.dark)
            .onAppear { revealed = true }
    }

    /// The way into the app.
    ///
    /// It used to be a bare row of three dots, which is what the drag grip is too:
    /// two dot clusters at opposite ends of the notch, one of which moved it and one
    /// of which opened a window, with nothing to say which was which. Enclosing it
    /// makes it read as a button rather than as texture, and it lights under the
    /// pointer so it answers before it is clicked.
    private var openButton: some View {
        Button(action: openDashboard) {
            ZStack {
                Circle().fill(.white.opacity(openHovered ? 0.22 : 0.10))
                Image(systemName: "ellipsis")
                    .font(.system(size: metrics.openGlyphType, weight: .semibold))
                    .foregroundStyle(openHovered ? NotchPalette.text : NotchPalette.muted)
            }
            .frame(width: metrics.openButton, height: metrics.openButton)
            // Padded well past the artwork: 22pt of circle is a small target on an
            // edge the pointer arrives at from outside the screen.
            .contentShape(Circle().inset(by: -7))
        }.buttonStyle(.plain)
            .onHover { hovering in
                guard !reduceMotion else { openHovered = hovering; return }
                withAnimation(.easeOut(duration: 0.12)) { openHovered = hovering }
            }
            .help("Open Brim")
            .accessibilityLabel("Open Brim")
    }

    private func item(_ tool: TrackedTool, sideBySide: Bool) -> some View {
        let window = store.headline(tool)
        let status = store.status(tool)
        let metrics = self.metrics
        let size = metrics.itemSize(anchor: placement, toolCount: store.activeTools.count)
        // Ring and number only. The provider's own mark identifies it, so a name
        // underneath repeated what the icon already said and cost a third of the
        // notch's height, and truncated to "ChatGPT W…" while doing it. The full
        // name is one hover away on the card.
        let ring = UsageRing(tool: tool, percent: window?.usedPercent, size: metrics.ring,
                             subdued: status == "Last known" || status == "Unavailable",
                             severity: window?.severity ?? .normal, surface: .notch,
                             busy: store.isRefreshing(tool))
        let number = Text(store.glanceValue(tool) ?? "·")
            .font(.system(size: metrics.numberType, weight: .medium, design: .rounded)).monospacedDigit()
            // The side-by-side layout gives the number a fixed slot, and a slot a
            // point too narrow wraps "100%" onto two lines rather than overflowing it.
            .lineLimit(1)
        return Button { onRefresh(tool) } label: {
            Group {
                if sideBySide {
                    HStack(spacing: metrics.rowNumberSpacing) {
                        ring
                        // A fixed width: the notch must not resize itself as the
                        // number crosses from 9% to 100%.
                        number.frame(width: metrics.rowNumberWidth)
                    }
                } else {
                    VStack(spacing: metrics.stackSpacing) { ring; number }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .onHover { onHover(tool, $0) }
            .contextMenu {
                // A described tool has no account page to open, since only the app that
                // wrote the file knows where its usage lives.
                if tool.builtin != nil { Button("Open \(tool.name) usage page") { openUsage(tool) } }
                Button("Refresh \(tool.name)") { onRefresh(tool) }
                Divider()
                Button("Keep open for 5 minutes") { onKeepOpen() }
                Button("Hide \(tool.name)") { onHide(tool) }
                Divider()
                Button("Open Brim") { openDashboard() }
            }
            .help("\(tool.name), click to refresh. Right-click for more.")
            .accessibilityLabel("\(tool.name), \(store.glanceDescription(tool))")
    }
}

struct CollapsedNotchView: View {
    let placement: NotchAnchor
    /// Passed in rather than derived: on a notched Mac the collapsed top notch is
    /// exactly the hardware notch, which is a property of the display.
    let size: CGSize
    /// Required rather than defaulted: a collapsed notch drawn at the designed size
    /// inside a frame sized for a larger one is the kind of mismatch nothing catches.
    let metrics: NotchMetrics
    let expand: () -> Void
    var body: some View {
        let pill = metrics.collapsedPill
        return Button(action: expand) {
            EdgeNotchShape(placement: placement, endCapDepth: metrics.collapsedCapDepth).fill(.black)
                .overlay(Capsule().fill(.white.opacity(0.4))
                    .frame(width: placement.isHorizontal ? pill.width : pill.height,
                           height: placement.isHorizontal ? pill.height : pill.width))
                .frame(width: size.width, height: size.height)
                // The collapsed notch can be 12pt across. The hit area is padded well
                // past the artwork so it can actually be hit.
                .contentShape(Rectangle().inset(by: -10))
        }.buttonStyle(.plain)
            .onHover { if $0 { expand() } }
            .help("Hover or click to expand Brim")
            .accessibilityLabel("Expand Brim")
    }
}

struct HoverDetailView: View {
    @ObservedObject var store: UsageStore
    let tool: TrackedTool
    var hover: (Bool) -> Void
    var connect: () -> Void
    var openUsage: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Button(action: openUsage) {
                HStack(spacing: 9) {
                    ToolMark(tool: tool, size: 24, tint: NotchPalette.text)
                    Text("\(tool.name) usage").font(.system(size: 17, weight: .medium)).tracking(-0.4)
                    Spacer()
                    if tool.builtin?.hasUsageLink ?? false {
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(NotchPalette.muted)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!(tool.builtin?.hasUsageLink ?? false)).help(tool.linkHint)
            if let scope = tool.scopeNote {
                Text(scope).font(.system(size: 10)).foregroundStyle(NotchPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
            let status = store.status(tool)
            if let reading = store.reading(tool), reading.hasReading {
                let headline = reading.headline(at: store.now)
                ForEach(reading.windows) { window in
                    UsageBar(window: window, now: store.now, emphasised: window.id == headline?.id, surface: .notch)
                }
                ForEach(reading.counts) { count in
                    HStack(spacing: 8) {
                        Text(count.title)
                        Spacer(minLength: 8)
                        Text(count.detail).monospacedDigit()
                            .foregroundStyle(count.remaining == 0 ? NotchPalette.usage(100) : NotchPalette.text)
                    }
                    .font(.system(size: 12))
                    .opacity(count.remaining == nil ? 0.6 : 1)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(count.title), \(count.detail)")
                }
                HStack(spacing: 5) {
                    Circle().fill(status == "Connected" ? NotchPalette.positive : NotchPalette.muted).frame(width: 4, height: 4)
                    Text(status == "Connected" ? reading.sourceLabel : status)
                    Spacer()
                    // When the reading was taken, not when it was displayed. This
                    // source can be hours or days behind and must say so.
                    Text("taken \(reading.updatedAt.formatted(.relative(presentation: .named)))")
                }.font(.system(size: 9)).foregroundStyle(NotchPalette.muted)
            } else {
                Text(store.emptyMessage(tool))
                    .font(.system(size: 12)).foregroundStyle(NotchPalette.muted).lineSpacing(4)
                if tool.builtin != nil {
                    Button("Set up \(tool.name)", action: connect).buttonStyle(QuietButton(prominent: true, surface: .notch))
                }
            }
        }.padding(20).frame(width: 300).background(.black, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
            .foregroundStyle(.white).preferredColorScheme(.dark).onHover(perform: hover)
    }
}

final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Sits between the panel and its SwiftUI content so the two never negotiate size
/// directly. See `installContent` for why that negotiation has to be broken.
final class HostingShell: NSView {}

@MainActor
final class NotchController {
    let store: UsageStore
    private var panel: PassivePanel?
    private var detail: PassivePanel?
    private var hideWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var layoutTimer: Timer?
    private var hoverTimer: Timer?
    private var lastLayout: NotchScreenLayout?
    private var presentedSize = NSSize.zero
    private var sideSize = NSSize.zero
    private var horizontalSize = NSSize.zero
    private var anchor: NotchAnchor?
    private var dragSession: NotchDragSession?
    private var slidePosition: NotchPosition?
    private var isSliding: Bool { dragSession != nil }
    private var revealState = NotchRevealState(collapseWhenIdle: false)
    private var isVisible: Bool { store.notchVisible }
    private var openDashboard: () -> Void
    private var openConnections: () -> Void
    private var targetScreen: NSScreen? { ScreenGeometry.target }
    private var metrics: NotchMetrics { NotchMetrics(store.notchSize) }

    init(store: UsageStore, openDashboard: @escaping () -> Void, openConnections: @escaping () -> Void) {
        self.store = store; self.openDashboard = openDashboard; self.openConnections = openConnections
        store.onLayoutChange = { [weak self] in self?.rebuild() }
        store.onPositionChange = { [weak self] in
            NotchPositionControl.cancelActiveDrag()
            self?.clearSlide(); self?.updateLayout(force: true)
        }
        store.onVisibilityChange = { [weak self] in
            NotchPositionControl.cancelActiveDrag()
            self?.clearSlide(); self?.updateLayout(force: true)
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        rebuild()
        // The Dock can move or resize without a display configuration change.
        // Re-read visibleFrame; only move windows when the usable bounds change.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateLayout() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        layoutTimer = timer
    }

    func rebuild() {
        NotchPositionControl.cancelActiveDrag()
        clearSlide()
        hoverTimer?.invalidate(); hoverTimer = nil
        hideWork?.cancel(); panel?.close(); detail?.close(); detail = nil; panel = nil
        anchor = nil
        lastLayout = nil
        revealState = NotchRevealState(collapseWhenIdle: store.collapseWhenIdle)
        guard targetScreen != nil, !store.activeTools.isEmpty else {
            store.setAutomaticPlacement(nil); return
        }
        sideSize = NSHostingView(rootView: fullView(at: .right)).fittingSize
        horizontalSize = NSHostingView(rootView: fullView(at: .bottom)).fittingSize
        panel = makePanel(frame: .zero)
        updateLayout(force: true)
    }

    private func fullView(at anchor: NotchAnchor) -> NotchView {
        NotchView(store: store, placement: anchor, onHover: { [weak self] tool, inside in
            if inside { self?.showDetail(tool) } else { self?.scheduleHide() }
        }, openDashboard: openDashboard, openUsage: { [weak self] tool in self?.openUsage(tool) },
                  onRefresh: { [weak self] tool in self?.store.refresh(tool) },
                  onKeepOpen: { [weak self] in self?.keepOpen() },
                  onHide: { [weak self] tool in self?.store.toggle(tool) },
                  onSlide: { [weak self] point, phase in self?.slide(point, phase: phase) })
    }

    /// Hold the notch open for a few minutes, for reading a card or moving it without
    /// it folding away under the cursor.
    private func keepOpen(for duration: TimeInterval = 300) {
        store.noteActivity()
        revealState.keepOpen(until: Date().addingTimeInterval(duration))
        installContent()
        updateLayout(force: true, animate: true)
    }

    private func installContent() {
        guard let panel, let anchor else { return }
        let view: AnyView
        if revealState.isExpanded {
            view = AnyView(fullView(at: anchor))
        } else {
            view = AnyView(CollapsedNotchView(placement: anchor, size: collapsedSize(for: anchor),
                                              metrics: metrics,
                                              expand: { [weak self] in self?.expand() }))
        }
        let host = NSHostingView(rootView: view)
        presentedSize = host.fittingSize
        host.sizingOptions = []
        // A hosting view set straight onto the panel negotiates its own size with the
        // window and can shrink it when the content briefly reports a smaller fitting
        // size, which is exactly what happens mid edge-change. A plain container in
        // between takes that negotiation away.
        let shell = HostingShell(frame: NSRect(origin: .zero, size: presentedSize))
        shell.autoresizingMask = [.width, .height]
        host.frame = shell.bounds
        host.autoresizingMask = [.width, .height]
        shell.addSubview(host)
        panel.contentView = shell
        panel.title = revealState.isExpanded ? "Brim" : "Brim edge"
    }

    private func collapsedSize(for anchor: NotchAnchor) -> CGSize {
        if anchor == .top, let cutout = currentLayout?.cutout {
            return CGSize(width: cutout.width, height: cutout.depth)
        }
        return metrics.collapsedSize(anchor)
    }

    /// The top edge has to reach the menu-bar layer to meet the hardware notch. Every
    /// other edge keeps the visibility level the user chose. "Desktop only" and top
    /// placement are genuinely contradictory, and top wins while it is selected.
    private func applyWindowLevel(_ panel: PassivePanel, anchor: NotchAnchor?) {
        panel.level = anchor == .top
            ? .statusBar
            : NSWindow.Level(rawValue: store.visibilityMode.windowLevel)
    }

    private func expand() {
        guard isVisible, panel?.isVisible == true, revealState.reveal() else { return }
        // Opening the notch is someone looking at their limits. Ask for a current
        // reading now rather than showing whatever the last tick happened to fetch.
        store.refreshForDisplay()
        installContent(); updateLayout(force: true, animate: true)
        guard store.collapseWhenIdle else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackPointer() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common); hoverTimer = timer
    }

    private func trackPointer() {
        guard !isSliding, let panel, panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        // The card sits 12pt from the notch. A margin smaller than that gap makes the
        // pointer "leave" while crossing between them, folding the notch mid-reach.
        let corridor: CGFloat = -16
        let inNotch = panel.isVisible && panel.occlusionState.contains(.visible)
            && panel.frame.insetBy(dx: corridor, dy: corridor).contains(point)
        let inDetail = detail.map { $0.isVisible && $0.occlusionState.contains(.visible)
            && $0.frame.insetBy(dx: corridor, dy: corridor).contains(point) } ?? false
        guard revealState.updatePointer(isInside: inNotch || inDetail || store.controlsMenuOpen, now: Date()) else { return }
        hoverTimer?.invalidate(); hoverTimer = nil
        hideWork?.cancel(); detail?.orderOut(nil)
        installContent(); updateLayout(force: true, animate: true)
    }

    private var currentLayout: NotchScreenLayout? { ScreenGeometry.current }

    private func updateLayout(force: Bool = false, animate: Bool = false) {
        guard let panel, let layout = currentLayout else {
            clearSlide()
            self.panel?.orderOut(nil); detail?.orderOut(nil); lastLayout = nil
            store.setAutomaticPlacement(nil); return
        }
        if let slidePosition,
           layout.notchFrame(size: slidePosition.anchor.isHorizontal ? horizontalSize : sideSize,
                             anchor: slidePosition.anchor, fraction: slidePosition.fraction) == nil {
            clearSlide()
        }
        guard let position = layout.resolvedPosition(preferred: slidePosition ?? store.preferredPosition,
                                                    sideSize: sideSize, horizontalSize: horizontalSize) else {
            anchor = nil; lastLayout = nil
            store.setAutomaticPlacement(nil)
            panel.orderOut(nil); detail?.orderOut(nil); return
        }
        let chosen = position.anchor
        let movedToAnotherEdge = anchor != chosen
        if movedToAnotherEdge {
            if !isSliding {
                hoverTimer?.invalidate(); hoverTimer = nil
                revealState = NotchRevealState(collapseWhenIdle: store.collapseWhenIdle)
            }
            anchor = chosen; store.setAutomaticPlacement(chosen)
            applyWindowLevel(panel, anchor: chosen)
            installContent()
        }
        guard force || movedToAnotherEdge || layout != lastLayout else { return }
        lastLayout = layout
        hideWork?.cancel(); detail?.orderOut(nil)
        let expandedSize = chosen.isHorizontal ? horizontalSize : sideSize
        guard isVisible, let frame = layout.notchFrame(size: presentedSize, anchor: chosen,
                                                      fraction: position.fraction, expandedSize: expandedSize) else {
            panel.orderOut(nil); return
        }
        let shouldAnimate = animate && !movedToAnotherEdge && panel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func slide(_ point: CGPoint, phase: NotchSlidePhase) {
        switch phase {
        case .began:
            guard isVisible, revealState.isExpanded, panel?.isVisible == true, let layout = currentLayout,
                  let position = layout.resolvedPosition(preferred: store.preferredPosition,
                                                         sideSize: sideSize, horizontalSize: horizontalSize) else { return }
            dragSession = NotchDragSession(position: position, pointer: point); slidePosition = position
            hideWork?.cancel(); detail?.orderOut(nil)
        case .moved, .ended:
            guard var session = dragSession, let layout = currentLayout else { return }
            guard let position = session.update(at: point, layout: layout, sideSize: sideSize, horizontalSize: horizontalSize) else {
                clearSlide(); updateLayout(force: true); return
            }
            dragSession = session
            slidePosition = position
            if phase == .ended {
                clearSlide(); store.savePosition(position)
            } else {
                updateLayout(force: true)
            }
        case .cancelled:
            clearSlide(); updateLayout(force: true)
        }
    }

    private func clearSlide() {
        dragSession = nil; slidePosition = nil
    }

    func stop() {
        NotchPositionControl.cancelActiveDrag()
        layoutTimer?.invalidate(); hoverTimer?.invalidate(); hideWork?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel?.close(); detail?.close()
    }

    private func showDetail(_ tool: TrackedTool) {
        hideWork?.cancel()
        store.refreshForDisplay()
        updateLayout()
        guard !isSliding, isVisible, revealState.isExpanded, let panel, panel.isVisible, let anchor, let layout = currentLayout else { return }
        let content = HoverDetailView(store: store, tool: tool, hover: { [weak self] inside in
            if inside { self?.hideWork?.cancel() } else { self?.scheduleHide() }
        }, connect: { [weak self] in self?.detail?.orderOut(nil); self?.openConnections() },
           openUsage: { [weak self] in self?.openUsage(tool) })
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let index = store.activeTools.firstIndex(of: tool) ?? 0
        // Asked of the metrics rather than recomputed here: a typed 56 once drifted
        // from the real item width, and the item is not one fixed size any more.
        let itemCenter = metrics.itemCenter(index: index, anchor: anchor, toolCount: store.activeTools.count)
        guard let frame = layout.detailFrame(size: size, notchFrame: panel.frame, anchor: anchor, itemCenterFromTop: itemCenter) else { detail?.orderOut(nil); return }
        if detail == nil { detail = makeDetailPanel(frame: frame) }
        host.frame = NSRect(origin: .zero, size: size)
        detail?.contentView = host; detail?.setFrame(frame, display: true)
        detail?.orderFrontRegardless()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.detail?.orderOut(nil) }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private func openUsage(_ tool: TrackedTool) {
        guard let provider = tool.builtin else { return }
        hideWork?.cancel(); detail?.orderOut(nil)
        store.openUsage?(provider)
    }
    /// The hover card, which is a different kind of window from the notch.
    ///
    /// The notch keeps the visibility level the user chose, and on the top edge sits
    /// at the menu bar. The card is a transient thing the pointer summoned, and it is
    /// the whole answer to "why is that ring orange", so it goes above all of that,
    /// including the window the user is working in. It previously inherited the
    /// notch's level and opened *underneath* that window, where nobody could read it.
    private func makeDetailPanel(frame: NSRect) -> PassivePanel {
        let panel = makePanel(frame: frame)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.hasShadow = true
        return panel
    }

    private func makePanel(frame: NSRect) -> PassivePanel {
        let panel = PassivePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        // Desktop mode stays below app windows, including the expanded notch
        // and its detail cards. Both modes remain below the Dock and menu bar.
        panel.level = NSWindow.Level(rawValue: store.visibilityMode.windowLevel)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if store.visibilityMode.joinsFullScreenApps { panel.collectionBehavior.insert(.fullScreenAuxiliary) }
        panel.isReleasedWhenClosed = false
        return panel
    }
}
