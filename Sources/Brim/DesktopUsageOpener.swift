import AppKit
import BrimCore

@MainActor
final class DesktopUsageOpener: DesktopUsageOpening {
    private let workspace = NSWorkspace.shared

    func isAvailable(_ route: DesktopUsageRoute) -> Bool { applicationURL(for: route) != nil }

    func open(_ route: DesktopUsageRoute) async throws {
        guard let applicationURL = applicationURL(for: route) else { throw OpenError.unavailable }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Pin the destination to the verified app, rather than an arbitrary
            // registered handler or the user's default browser.
            workspace.open([route.url], withApplicationAt: applicationURL, configuration: configuration) { application, error in
                if let error { continuation.resume(throwing: error) }
                else if application?.bundleIdentifier == route.bundleIdentifier { continuation.resume() }
                else { continuation.resume(throwing: OpenError.unavailable) }
            }
        }
    }

    private func applicationURL(for route: DesktopUsageRoute) -> URL? {
        guard let url = workspace.urlForApplication(withBundleIdentifier: route.bundleIdentifier),
              let bundle = Bundle(url: url) else { return nil }
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard route.supports(bundleIdentifier: bundle.bundleIdentifier,
                             version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                             schemes: schemes) else { return nil }
        return url
    }

    private enum OpenError: Error { case unavailable }
}
