import AppKit
import SwiftUI
import BrimCore

/// The app's window colours.
///
/// Everything here is a system colour or an explicit light/dark pair, so the window
/// belongs to whatever appearance the Mac is in rather than forcing its own. Earlier
/// versions hardcoded a white palette and pinned the window to Aqua, which made the
/// app look like a web page someone had embedded in a Mac.
///
/// Deliberately separate from `NotchPalette`. The notch stays black because it has to
/// merge with the MacBook's physical notch, a hardware constraint rather than a styling
/// choice, so the two surfaces cannot share one palette. Shared components take a
/// `Surface` and pick the right one.
enum Palette {
    /// A colour that resolves per appearance, so one definition covers both modes.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static let background = Color(nsColor: .windowBackgroundColor)
    /// The surface a grouped row sits on.
    static let card = Color(nsColor: .controlBackgroundColor)
    static let line = Color(nsColor: .separatorColor)
    static let text = Color.primary
    static let muted = Color.secondary
    /// Follows the accent colour chosen in System Settings.
    static let accent = Color.accentColor
    static let positive = adaptive(light: NSColor(srgbRed: 0.043, green: 0.522, blue: 0.361, alpha: 1),
                                   dark: NSColor(srgbRed: 0.30, green: 0.94, blue: 0.66, alpha: 1))

    /// The usage ramp, in both appearances.
    ///
    /// The light values are darker and more saturated: the bright greens and yellows
    /// that read well on the notch's black are close to invisible on a white sheet, and
    /// the reverse is true in dark mode.
    static func usage(_ percent: Double) -> Color {
        if percent >= 90 { return adaptive(light: NSColor(srgbRed: 0.816, green: 0.157, blue: 0.157, alpha: 1),
                                           dark: NSColor(srgbRed: 1, green: 0.36, blue: 0.36, alpha: 1)) }
        if percent >= 70 { return adaptive(light: NSColor(srgbRed: 0.851, green: 0.353, blue: 0.047, alpha: 1),
                                           dark: NSColor(srgbRed: 1, green: 0.45, blue: 0.22, alpha: 1)) }
        if percent >= 50 { return adaptive(light: NSColor(srgbRed: 0.706, green: 0.478, blue: 0.043, alpha: 1),
                                           dark: NSColor(srgbRed: 0.93, green: 0.86, blue: 0.34, alpha: 1)) }
        return positive
    }

    /// A provider's own severity outranks the percentage ramp. Claude can call 84%
    /// a warning while the ramp would still read it as merely high, and the provider
    /// knows which of its limits actually bites.
    static func usage(_ percent: Double, severity: UsageSeverity) -> Color {
        switch severity {
        case .critical: usage(95)
        case .warning: usage(75)
        case .normal: usage(percent)
        }
    }
}

/// The notch itself, which stays dark whatever the app looks like.
enum NotchPalette {
    static let surface = Color.black
    static let text = Color.white
    static let line = Color.white.opacity(0.09)
    static let muted = Color(red: 0.60, green: 0.64, blue: 0.68)
    static let accent = Color(red: 0.44, green: 0.66, blue: 1.0)
    static let positive = Color(red: 0.30, green: 0.94, blue: 0.66)

    static func usage(_ percent: Double) -> Color {
        if percent >= 90 { return Color(red: 1, green: 0.36, blue: 0.36) }
        if percent >= 70 { return Color(red: 1, green: 0.45, blue: 0.22) }
        if percent >= 50 { return Color(red: 0.93, green: 0.86, blue: 0.34) }
        return Color(red: 0.30, green: 0.94, blue: 0.66)
    }

    static func usage(_ percent: Double, severity: UsageSeverity) -> Color {
        switch severity {
        case .critical: Color(red: 1, green: 0.36, blue: 0.36)
        case .warning: Color(red: 1, green: 0.45, blue: 0.22)
        case .normal: usage(percent)
        }
    }
}

/// Which surface a shared component is being drawn on.
///
/// A ring or a bar appears both in the window and in the notch's hover card, and the
/// two need opposite contrast. Passing the surface is clearer than reading the colour
/// scheme, because the notch is black even when the Mac is in light mode.
enum Surface {
    case app, notch

    var text: Color { self == .app ? Palette.text : NotchPalette.text }
    var muted: Color { self == .app ? Palette.muted : NotchPalette.muted }
    var accent: Color { self == .app ? Palette.accent : NotchPalette.accent }
    var positive: Color { self == .app ? Palette.positive : NotchPalette.positive }
    var line: Color { self == .app ? Palette.line : NotchPalette.line }
    /// The colour sitting behind the component, for knocked-out details.
    var behind: Color { self == .app ? Palette.card : NotchPalette.surface }
    /// The unfilled part of a ring or bar.
    var track: Color {
        self == .app ? Color(nsColor: .quaternaryLabelColor) : Color.white.opacity(0.13)
    }

    func usage(_ percent: Double) -> Color {
        self == .app ? Palette.usage(percent) : NotchPalette.usage(percent)
    }
    func usage(_ percent: Double, severity: UsageSeverity) -> Color {
        self == .app ? Palette.usage(percent, severity: severity)
                     : NotchPalette.usage(percent, severity: severity)
    }
}
