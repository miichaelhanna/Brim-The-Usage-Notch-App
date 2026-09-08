import Foundation

public struct DesktopUsageRoute: Equatable, Sendable {
    public let bundleIdentifier: String
    public let url: URL
    public let minimumVersion: String

    public func supports(bundleIdentifier: String?, version: String?, schemes: [String]) -> Bool {
        guard bundleIdentifier == self.bundleIdentifier, let version,
              version.compare(minimumVersion, options: .numeric) != .orderedAscending,
              let scheme = url.scheme else { return false }
        return schemes.contains { $0.caseInsensitiveCompare(scheme) == .orderedSame }
    }
}

public extension Provider {
    /// Destinations verified in the installed desktop apps.
    var desktopUsageRoute: DesktopUsageRoute? {
        switch self {
        case .claude, .claudeCode:
            return DesktopUsageRoute(bundleIdentifier: "com.anthropic.claudefordesktop",
                                     url: URL(string: "claude://claude.ai/settings/usage")!, minimumVersion: "1.46388.4")
        case .chatgpt, .codex:
            // `settings/usage` is the app's own Usage & billing pane, and `usage` is one
            // of the sections its deep-link handler accepts.
            //
            // This used to go to the app's `browser` host with the web page as a query
            // parameter, on the belief that /usage was not accepted. That host loads a
            // URL into the app's browser panel, so clicking ChatGPT opened a web view of
            // chatgpt.com rather than the native settings pane. The page it landed on
            // meters the same Work allowance, which is why the bug survived review.
            return DesktopUsageRoute(bundleIdentifier: "com.openai.codex",
                                     url: URL(string: "codex://settings/usage")!, minimumVersion: "26.901.51231")
        }
    }

    var usageLinkHint: String { "Open \(name)’s own usage page" }
}

@MainActor
public protocol DesktopUsageOpening {
    func isAvailable(_ route: DesktopUsageRoute) -> Bool
    func open(_ route: DesktopUsageRoute) async throws
}

@MainActor
public final class UsageLinkRouter {
    private let opener: any DesktopUsageOpening
    private let showInBrim: (Provider) -> Void
    private var latestRequest = UUID()

    public init(opener: any DesktopUsageOpening, showInBrim: @escaping (Provider) -> Void) {
        self.opener = opener; self.showInBrim = showInBrim
    }

    public func open(_ provider: Provider) async {
        let request = UUID(); latestRequest = request
        guard let route = provider.desktopUsageRoute, opener.isAvailable(route) else {
            showInBrim(provider); return
        }
        do { try await opener.open(route) }
        catch {
            // A late failure must not take focus away from a newer label click.
            guard request == latestRequest, !Task.isCancelled else { return }
            showInBrim(provider)
        }
    }
}
