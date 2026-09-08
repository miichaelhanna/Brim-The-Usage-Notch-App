import Foundation
import ServiceManagement

/// Opening at login, re-asserted on every launch.
///
/// Brim is a menu bar item, and a menu bar item whose app is not running is not there
/// at all. Registering once on the first run was not enough to keep it there: a
/// registration that failed that day was never retried, and one made from a copy of
/// the app that has since moved points at a bundle macOS can no longer find. Either
/// way the menu bar comes up empty after a restart and nothing ever puts it back.
///
/// So the registration is asserted at every launch instead, from whichever copy of
/// Brim is actually running. Two things stop it, and both are someone's decision
/// rather than a fault: turning the switch off in Settings, which is remembered here,
/// and turning Brim off in System Settings › General › Login Items, which shows up as
/// `requiresApproval` and is left alone.
enum LoginItem {
    /// Only the off state is stored. Absent means on, so an install that predates this
    /// switch starts out opening at login, as it did.
    private static let offKey = "openAtLoginOff"

    private static var service: SMAppService { .mainApp }

    static var isOff: Bool { UserDefaults.standard.bool(forKey: offKey) }
    static var status: SMAppService.Status { service.status }
    static var isEnabled: Bool { status == .enabled }
    /// Registered, then switched off by hand in System Settings.
    static var needsApproval: Bool { status == .requiresApproval }

    /// Called on every launch. Silent: nobody asked for this, so a failure is not worth
    /// a dialog. The switch in Settings reports the real state when someone looks.
    static func assertRegistered() {
        guard !isOff, status == .notRegistered else { return }
        try? service.register()
    }

    static func set(_ on: Bool) throws {
        UserDefaults.standard.set(!on, forKey: offKey)
        if on { try service.register() }
        // Unregistering something macOS has no record of throws, and turning off a
        // switch that was already off is not a failure worth reporting.
        else if status != .notRegistered { try service.unregister() }
    }

    /// The Login Items pane, for the one state Brim cannot change from here.
    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
