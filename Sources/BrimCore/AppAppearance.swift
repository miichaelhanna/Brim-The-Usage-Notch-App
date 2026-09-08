import Foundation

/// Which appearance the window uses.
///
/// A Mac app normally just follows the system, and that stays the default. The override
/// exists because this app is looked at beside a black notch all day, and some people
/// want the window to match it whatever the rest of the Mac is doing.
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// Reads a saved value, falling back to following the system.
    public init(saved: String?) {
        self = AppAppearance(rawValue: saved ?? "") ?? .system
    }
}
