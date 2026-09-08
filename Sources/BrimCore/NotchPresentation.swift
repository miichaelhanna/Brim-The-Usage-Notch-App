import Foundation
import CoreGraphics

public enum NotchVisibilityMode: String, CaseIterable, Identifiable, Sendable {
    case overApps, desktopOnly
    public var id: String { rawValue }
    public var title: String { self == .overApps ? "Over apps" : "Desktop only" }
    public var windowLevel: Int {
        self == .overApps
            ? Int(CGWindowLevelForKey(.floatingWindow))
            : Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    }
    public var joinsFullScreenApps: Bool { self == .overApps }
}

/// Where the app shows up outside its notch.
///
/// The menu bar item is always there. It is where usage and every control live, and
/// earlier builds let it be switched off, which left the notch as the only way in. A
/// hidden notch then meant a hidden app. The one choice left is whether the Dock shows
/// it too.
public enum AppPresence: String, CaseIterable, Identifiable, Sendable {
    case menuBar, both
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .menuBar: "Menu bar only"
        case .both: "Menu bar and Dock"
        }
    }
    public var showsDockIcon: Bool { self == .both }

    /// Reads a saved value, including ones from builds that allowed hiding the menu
    /// bar item. "Dock only" keeps its Dock icon and gains the menu bar; "Neither"
    /// becomes the menu bar alone.
    public init(saved: String?) {
        switch saved {
        case "both", "dock": self = .both
        default: self = .menuBar
        }
    }
}

/// Keeps the notch expanded while crossing into a usage card. A short delay
/// prevents a brief pointer exit from folding the controls away mid-interaction.
public struct NotchRevealState {
    public let collapseWhenIdle: Bool
    public private(set) var isExpanded: Bool
    private var collapseDeadline: Date?
    /// A temporary pin. While it holds, the notch stays open even when the pointer
    /// leaves, for reading a card, or dragging the notch somewhere else without it
    /// folding away underneath the cursor.
    private var pinnedUntil: Date?

    public init(collapseWhenIdle: Bool) {
        self.collapseWhenIdle = collapseWhenIdle
        isExpanded = !collapseWhenIdle
    }

    @discardableResult
    public mutating func reveal() -> Bool {
        let changed = !isExpanded
        isExpanded = true; collapseDeadline = nil
        return changed
    }

    /// Hold the notch open until `deadline`, whatever the pointer does.
    public mutating func keepOpen(until deadline: Date) {
        isExpanded = true
        collapseDeadline = nil
        pinnedUntil = deadline
    }

    public func isPinned(at now: Date) -> Bool { pinnedUntil.map { now < $0 } ?? false }

    /// Release the pin early.
    public mutating func releasePin() { pinnedUntil = nil }

    @discardableResult
    public mutating func updatePointer(isInside: Bool, now: Date) -> Bool {
        guard collapseWhenIdle, isExpanded else { return false }
        if isPinned(at: now) { collapseDeadline = nil; return false }
        if isInside { collapseDeadline = nil; return false }
        guard let deadline = collapseDeadline else {
            collapseDeadline = now.addingTimeInterval(0.35); return false
        }
        guard now >= deadline else { return false }
        isExpanded = false; collapseDeadline = nil
        return true
    }

    public static let collapsedSize = CGSize(width: 12, height: 72)
}
