import Foundation
import BrimCore

enum DockPositionReader {
    static func current() -> DockPosition {
        let domain = "com.apple.dock" as CFString
        // Refresh this read-only preference domain so moves are detected even
        // while the Dock is hidden and NSScreen.visibleFrame is unchanged.
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String
        return value.flatMap(DockPosition.init(rawValue:)) ?? .bottom
    }
}
