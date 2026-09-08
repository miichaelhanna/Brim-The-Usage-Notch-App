import AppKit
import SwiftUI
import BrimCore

enum NotchSlidePhase {
    case began, moved, ended, cancelled
}

/// A grip inside the notch. Dragging it moves the notch along its edge and onto
/// another available edge; a click alone does nothing, so the notch can never be
/// moved by accident.
struct NotchPositionControl: NSViewRepresentable {
    let onDrag: (CGPoint, NotchSlidePhase) -> Void
    /// The dots grow with the notch. Left at their designed size inside a grip that
    /// scales, they read as a smaller and smaller speck at the end of a larger and
    /// larger strip, and the notch stops looking like one drawing.
    var scale: CGFloat = 1

    func makeNSView(context: Context) -> NotchGripView {
        let view = NotchGripView()
        view.onDrag = onDrag
        view.scale = scale
        return view
    }

    func updateNSView(_ view: NotchGripView, context: Context) {
        view.onDrag = onDrag
        view.scale = scale
    }

    // Deliberately no dismantleNSView. Changing edges mid-drag replaces the
    // hosting view, and cancelling here would abort the gesture the user is still
    // making. The drag lives in NotchDragMonitor, which outlives the view; the
    // controller cancels it explicitly when it genuinely stops.

    static func cancelActiveDrag() {
        NotchDragMonitor.shared.cancel()
    }
}

/// Owns the drag independently of any view or window.
///
/// The gesture has to survive `NotchController.installContent()` swapping the
/// hosting view when the notch changes edge, so the events are taken from a local
/// monitor on the application rather than from the view's own mouse handlers. The
/// panel that received the mouse-down keeps the implicit grab, so its drag and
/// mouse-up events keep arriving even after its content view has been replaced.
@MainActor
final class NotchDragMonitor {
    static let shared = NotchDragMonitor()

    private var monitor: Any?
    private var handler: ((CGPoint, NotchSlidePhase) -> Void)?
    private var origin: CGPoint?
    private var started = false
    private var cursorPushed = false

    /// Movement, in any direction, before a press becomes a drag.
    private static let threshold: CGFloat = 4

    func begin(origin: CGPoint, handler: @escaping (CGPoint, NotchSlidePhase) -> Void) {
        cancel()
        self.origin = origin
        self.handler = handler
        started = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            let type = event.type
            guard type == .leftMouseDragged || type == .leftMouseUp || type == .keyDown else { return event }
            // keyCode traps on a mouse event, so it is only read for a key event.
            let isEscape = type == .keyDown && event.keyCode == 53
            let point = Self.screenPoint(for: event)
            // AppKit delivers local monitors on the main thread. NSEvent is not
            // Sendable, so only plain values cross into the isolated call.
            let handled = MainActor.assumeIsolated { self.handle(type: type, isEscape: isEscape, point: point) }
            return handled ? nil : event
        }
    }

    func cancel() {
        guard origin != nil else { return }
        let wasDragging = started
        let handler = self.handler
        let point = NSEvent.mouseLocation
        // Release the monitor and the cursor before the callback: it may rebuild or
        // stop the controller, and must not find a live session still installed.
        clear()
        if wasDragging { handler?(point, .cancelled) }
    }

    /// Returns true when the event was consumed, so it is not also processed by
    /// the view underneath.
    private func handle(type: NSEvent.EventType, isEscape: Bool, point: CGPoint) -> Bool {
        guard let origin else { return false }
        switch type {
        case .leftMouseDragged:
            if !started {
                guard hypot(point.x - origin.x, point.y - origin.y) >= Self.threshold else { return true }
                started = true
                pushCursor()
                // Begin from the grab point, so the notch keeps the offset the user
                // grabbed it at instead of jumping its centre under the pointer.
                handler?(origin, .began)
            }
            handler?(point, .moved)
            return true
        case .leftMouseUp:
            let wasDragging = started
            let handler = self.handler
            // Release the monitor and cursor before the callback: it may rebuild or
            // stop the controller, and must not find a live session still installed.
            clear()
            if wasDragging { handler?(point, .ended) }
            return true
        case .keyDown:
            // Best effort only: a local monitor sees key events just while this app
            // holds keyboard focus, and the notch is a non-activating panel.
            guard isEscape else { return false }
            cancel()
            return true
        default:
            return false
        }
    }

    private func clear() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
        origin = nil
        started = false
        popCursor()
    }

    private func pushCursor() {
        guard !cursorPushed else { return }
        NSCursor.closedHand.push()
        cursorPushed = true
    }

    private func popCursor() {
        guard cursorPushed else { return }
        NSCursor.pop()
        cursorPushed = false
    }

    /// Use the point recorded with each event, including queued events from a fast
    /// drag. Reading the live pointer here would give every handler the end point,
    /// which makes a quick drag read as a click.
    nonisolated static func screenPoint(for event: NSEvent) -> CGPoint {
        if let point = event.cgEvent?.location, let primary = NSScreen.screens.first {
            return CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        }
        // Converting through the event's window would need the main actor, which
        // this deliberately does not require. Every event a local monitor receives
        // from real input carries a CGEvent, so that path is the normal one.
        return NSEvent.mouseLocation
    }
}

@MainActor
final class NotchGripView: NSView {
    var onDrag: ((CGPoint, NotchSlidePhase) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel("Move Brim")
        let help = "Drag to move the notch along this edge or onto another one. "
            + "Every edge is available except the Dock's, which is skipped. "
            + "Settings and the menu bar item's Position menu can choose an edge directly."
        setAccessibilityHelp(help)
        toolTip = "Drag to move Brim"
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let onDrag else { return }
        NotchDragMonitor.shared.begin(origin: NotchDragMonitor.screenPoint(for: event), handler: onDrag)
    }

    /// The dot grid, as figures rather than as literals in `draw`. The notch's
    /// padding is measured to the dots the user can see, not to this view's frame,
    /// so it has to be able to ask how much of the frame the dots actually use.
    nonisolated private static let dotSpacing: CGFloat = 6.5
    nonisolated private static let dotRadius: CGFloat = 1.4
    /// Whichever way the grip is turned, two dots lie along the strip and three
    /// across it, so the ink along the strip is one gap plus one dot.
    nonisolated static var inkAlongStrip: CGFloat { dotSpacing + dotRadius * 2 }
    /// Set by the layout, which knows the notch's size. Only the drawing uses it;
    /// the frame is given to this view already scaled.
    var scale: CGFloat = 1 { didSet { guard scale != oldValue else { return }; needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.45).setFill()
        // The dots lie along the strip they are in: wide across the top of a side
        // notch, tall down the end of a top or bottom one. A fixed 2×3 grid read as
        // portrait wherever it was put, which fought the strip on every side edge.
        let alongStrip = 3, acrossStrip = 2
        let isWide = bounds.width >= bounds.height
        let columns = isWide ? alongStrip : acrossStrip
        let rows = isWide ? acrossStrip : alongStrip
        let spacing = Self.dotSpacing * scale, radius = Self.dotRadius * scale
        let originX = bounds.midX - CGFloat(columns - 1) * spacing / 2
        let originY = bounds.midY - CGFloat(rows - 1) * spacing / 2
        for column in 0..<columns {
            for row in 0..<rows {
                let center = CGPoint(x: originX + CGFloat(column) * spacing,
                                     y: originY + CGFloat(row) * spacing)
                NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)).fill()
            }
        }
    }
}
