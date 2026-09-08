import XCTest
@testable import BrimCore

@MainActor
private final class FakeDesktopOpener: DesktopUsageOpening {
    var available = true
    var fails = false
    var opened: [DesktopUsageRoute] = []
    var pause = false
    var pending: CheckedContinuation<Void, Error>?
    var onOpen: (() -> Void)?
    enum Failure: Error { case launchFailed }
    func isAvailable(_ route: DesktopUsageRoute) -> Bool { available }
    func open(_ route: DesktopUsageRoute) async throws {
        opened.append(route)
        if pause {
            try await withCheckedThrowingContinuation { pending = $0; onOpen?() }
        } else if fails { throw Failure.launchFailed }
    }
}

final class UsageLinkRouterTests: XCTestCase {
    @MainActor
    func testInstalledSupportedAppOpensWithoutFallback() async {
        let opener = FakeDesktopOpener()
        var fallback: [Provider] = []
        let router = UsageLinkRouter(opener: opener) { fallback.append($0) }
        await router.open(.claude)
        XCTAssertEqual(opener.opened.map(\.url.absoluteString), ["claude://claude.ai/settings/usage"])
        XCTAssertTrue(fallback.isEmpty)
    }

    @MainActor
    func testEveryMissingDesktopAppOpensItsOwnBrimView() async {
        let opener = FakeDesktopOpener(); opener.available = false
        var fallback: [Provider] = []
        let router = UsageLinkRouter(opener: opener) { fallback.append($0) }
        for provider in Provider.allCases { await router.open(provider) }
        XCTAssertEqual(fallback, Provider.allCases)
        XCTAssertTrue(opener.opened.isEmpty)
    }

    @MainActor
    func testLaunchFailureFallsBackToTheClickedProvider() async {
        let opener = FakeDesktopOpener(); opener.fails = true
        var fallback: [Provider] = []
        let router = UsageLinkRouter(opener: opener) { fallback.append($0) }
        await router.open(.codex)
        XCTAssertEqual(fallback, [.codex])
    }

    /// One ring, one page: the ChatGPT ring shows the Work allowance Codex meters, so
    /// its link opens the page that shows that number rather than a settings screen.
    @MainActor
    func testChatGPTOpensTheSharedWorkUsagePage() async {
        let opener = FakeDesktopOpener()
        var fallback: [Provider] = []
        let router = UsageLinkRouter(opener: opener) { fallback.append($0) }
        await router.open(.chatgpt)
        XCTAssertEqual(opener.opened.first?.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(Provider.chatgpt.desktopUsageRoute, Provider.codex.desktopUsageRoute)
        XCTAssertEqual(Provider.chatgpt.accountURL, Provider.codex.accountURL)
        XCTAssertTrue(fallback.isEmpty)
    }

    func testClaudeCodeUsesTheSharedDesktopUsagePage() {
        XCTAssertEqual(Provider.claudeCode.desktopUsageRoute, Provider.claude.desktopUsageRoute)
    }

    /// The native Usage & billing pane, not the app's browser panel. Asserted field by
    /// field because `browser` with the web page as a query parameter also "worked":
    /// it opened, it showed the right numbers, and it was still a web view.
    func testCodexOpensTheNativeUsageSettingsPane() throws {
        let route = try XCTUnwrap(Provider.codex.desktopUsageRoute)
        let components = try XCTUnwrap(URLComponents(url: route.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(route.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(components.scheme, "codex")
        XCTAssertEqual(components.host, "settings")
        XCTAssertEqual(components.path, "/usage")
        XCTAssertNil(components.queryItems)
    }

    func testDesktopDetectionRequiresExpectedAppVersionAndScheme() throws {
        let route = try XCTUnwrap(Provider.claude.desktopUsageRoute)
        XCTAssertTrue(route.supports(bundleIdentifier: route.bundleIdentifier, version: "1.46388.4", schemes: ["claude"]))
        XCTAssertTrue(route.supports(bundleIdentifier: route.bundleIdentifier, version: "1.46388.10", schemes: ["CLAUDE"]))
        XCTAssertFalse(route.supports(bundleIdentifier: "com.example.other", version: "9.0", schemes: ["claude"]))
        XCTAssertFalse(route.supports(bundleIdentifier: route.bundleIdentifier, version: "0.9", schemes: ["claude"]))
        XCTAssertFalse(route.supports(bundleIdentifier: route.bundleIdentifier, version: nil, schemes: ["claude"]))
        XCTAssertFalse(route.supports(bundleIdentifier: route.bundleIdentifier, version: "9.0", schemes: ["https"]))
    }

    @MainActor
    func testLateLaunchFailureDoesNotOverrideNewerClick() async {
        let opener = FakeDesktopOpener(); opener.pause = true
        let started = expectation(description: "Desktop launch started")
        opener.onOpen = { started.fulfill() }
        var fallback: [Provider] = []
        let router = UsageLinkRouter(opener: opener) { fallback.append($0) }
        let firstClick = Task { await router.open(.claude) }
        await fulfillment(of: [started], timeout: 2)
        // The second click has no desktop app to go to, so it shows in Brim at once.
        opener.available = false
        await router.open(.chatgpt)
        opener.pending?.resume(throwing: FakeDesktopOpener.Failure.launchFailed)
        await firstClick.value
        XCTAssertEqual(fallback, [.chatgpt])
    }
}
