import Foundation
import BrimCore

/// What Brim looks for on this Mac.
///
/// Detection is filesystem-only and cheap, and it is only ever a list: finding a tool
/// is not permission to read it. Nothing is read until Connect is pressed for that
/// tool, and connecting still means no API key and no second login, because it hands
/// off to a sign-in the tool already has.
///
/// Only tools the app can actually read are listed. Earlier builds also detected tools
/// they could not read and showed them as "not supported yet", which put a list of
/// disappointments on the first screen. The way in for anything else is the project
/// itself: describe the tool (see Docs/add-a-tool.md) or contribute an adapter.
enum KnownTool: String, CaseIterable, Identifiable {
    case claudeCode, codex, perplexity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "ChatGPT & Codex"
        case .perplexity: "Perplexity"
        }
    }

    /// The providers this tool reports usage for, the displayed one first.
    var providers: [Provider] {
        switch self {
        case .claudeCode: [.claude, .claudeCode]
        case .codex: [.chatgpt, .codex]
        case .perplexity: [.perplexity]
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private var candidates: [String] {
        let home = Self.home.path
        switch self {
        case .claudeCode:
            // Claude Code, and only Claude Code. `/Applications/Claude.app` is the
            // Claude desktop app, which is a different product: it stores a different
            // Keychain item, and that item cannot read usage. Counting it here offered
            // a Claude Code row to people who had never installed Claude Code, whose
            // Connect button could only ever do nothing, silently.
            return ["\(home)/.claude.json", "\(home)/.claude", "\(home)/.local/bin/claude",
                    "\(home)/.bun/bin/claude", "\(home)/.volta/bin/claude",
                    "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        case .codex:
            return ["\(home)/.codex/auth.json", "\(home)/.codex",
                    "/Applications/ChatGPT.app", "/Applications/Codex.app"]
        case .perplexity:
            return ["/Applications/Perplexity.app", "\(home)/Applications/Perplexity.app"]
        }
    }

    /// Detection looks for the application or its executable, never for a config
    /// folder alone. Uninstalling leaves dot-directories behind, and reporting one of
    /// those as an installed tool is worse than missing it.
    var isInstalled: Bool {
        candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    static var installed: [KnownTool] { allCases.filter(\.isInstalled) }
}

/// What Brim can honestly say about a tool right now.
///
/// Detection only looks for files, so finding a tool says nothing about whether its
/// account is signed in. First run used to label everything it found "Ready", which
/// was a claim about sign-in it had never checked: someone with the ChatGPT app
/// installed but signed out was told it was ready and then shown an empty ring.
///
/// Shared by first run and Connections so the two screens cannot tell different
/// stories about the same tool.
struct ToolConnection {
    enum Status {
        /// Not connected. Nothing has been read from this tool, and nothing will be.
        case off
        /// Connected, and the first answer hasn't come back yet. Not signed out.
        case checking
        case connected
        /// Connected, but the tool itself is signed out. Brim can start its sign-in.
        case needsSignIn
        case problem
    }
    var status: Status
    var detail: String

    var isConnected: Bool { status == .connected }
    var isProblem: Bool { status == .problem }
    /// What the toggle reads: consent given, whatever the tool then has to say. The
    /// switch is the consent, not the sign-in, so a signed-out tool leaves it on.
    var isOn: Bool { status != .off }
}

extension KnownTool {
    /// What this tool is worth saying about it right now.
    ///
    /// Nothing is connected until it is asked for, so this leads with that rather than
    /// with anything read: before Connect, there is nothing read to report.
    @MainActor func connection(in store: UsageStore) -> ToolConnection {
        guard store.isConnected(self) else {
            return ToolConnection(status: .off, detail: offer)
        }
        switch self {
        case .claudeCode:
            if let error = store.errors[.claudeCode] { return ToolConnection(status: .problem, detail: error) }
            if store.liveClaude == .on {
                return ToolConnection(status: .connected, detail: "Live · one allowance for Claude chat, Claude Code and Claude Design")
            }
            if store.liveClaude == .checking || !store.checkedProviders.contains(.claudeCode) {
                return ToolConnection(status: .checking, detail: "Checking the Claude Code sign-in on this Mac…")
            }
            // A live read that has failed is the honest headline, even while a cached
            // reading is still on screen: it is the reason the number stopped moving.
            // Reporting the cache instead left this row green and reassuring directly
            // above the orange sentence saying the login had lapsed, and told first run,
            // which has no such sentence, nothing at all.
            if case .problem(let message) = store.liveClaude {
                return ToolConnection(status: .problem, detail: message)
            }
            if store.signedInProviders.contains(.claudeCode) {
                return ToolConnection(status: .connected,
                                      detail: "Signed in, showing Claude Code’s cached reading. "
                                      + "Allow the live read for current numbers.")
            }
            return ToolConnection(status: .needsSignIn,
                                  detail: "Sign in with Claude Code to read your allowance. It is what "
                                  + "holds the login Brim reads; the Claude app alone leaves none.")
        case .codex:
            if let error = store.errors[.codex] { return ToolConnection(status: .problem, detail: error) }
            if store.signedInProviders.contains(.codex) {
                return ToolConnection(status: .connected, detail: "Live · one Work allowance for ChatGPT and Codex")
            }
            if !store.checkedProviders.contains(.codex) {
                return ToolConnection(status: .checking, detail: "Checking the ChatGPT app’s sign-in…")
            }
            return ToolConnection(status: .needsSignIn,
                                  detail: "The ChatGPT app is signed out. Sign in to read the Work allowance.")
        case .perplexity:
            if let error = store.errors[.perplexity] { return ToolConnection(status: .problem, detail: error) }
            if store.signedInProviders.contains(.perplexity) {
                return ToolConnection(status: .connected, detail: "Live · counts from the Perplexity app")
            }
            if !store.checkedProviders.contains(.perplexity) {
                return ToolConnection(status: .checking, detail: "Looking for what Perplexity has recorded…")
            }
            return ToolConnection(status: .needsSignIn,
                                  detail: "Perplexity hasn’t recorded any usage on this Mac yet. "
                                  + "Sign in to Perplexity and run a search.")
        }
    }

    /// What connecting would do, said before it is done rather than after.
    private var offer: String {
        switch self {
        case .claudeCode:
            "Not connected. Connect to read your Claude allowance — chat, Code and Design share "
                + "one — from the login Claude Code already keeps on this Mac."
        case .codex:
            "Not connected. Connect to read the Work allowance ChatGPT and Codex share, through "
                + "the ChatGPT app’s own sign-in. No API key needed."
        case .perplexity:
            "Not connected. Connect to read what Perplexity has left from the preferences its "
                + "Mac app already writes. Counts, not a percentage: Perplexity never says what "
                + "the allowance was."
        }
    }
}
