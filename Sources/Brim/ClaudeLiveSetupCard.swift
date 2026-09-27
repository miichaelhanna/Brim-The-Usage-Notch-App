import AppKit
import SwiftUI
import BrimCore

/// Turning on live Claude updates, in Connections.
///
/// There is nothing to paste and nothing to mint. Claude Code already holds a login
/// that can read this account's usage, and the whole of "connecting" is letting Brim
/// read it. macOS asks about that once, in its own dialog.
///
/// First run does not use this. What a newcomer needs is the one-time approval, which
/// every provider can produce, and `ConnectApprovalPreview` says that once for all of
/// them rather than once per tool.
struct ClaudeLiveSetupCard: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if store.claudeSetupStep != .idle {
                ClaudeSetupProgress(store: store)
            } else if store.claudeNeedsSignIn {
                signInOffer
            } else {
                switch store.liveClaude {
            case .on: connected
            case .checking: checking
            case .off: offered
            case .problem: problem
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // No card of its own: this always sits inside a grouped form section, which
        // already provides the surface.
        .padding(.vertical, 2)
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Live Claude updates are on").font(.headline)
                Spacer()
            }
            Text("One allowance covers Claude chat, Claude Code and Claude Design, and this is it. "
                 + "Brim reads the login Claude Code already keeps on this Mac, and only reads it. It "
                 + "cannot expire, rotate or invalidate that login, so it cannot sign you out of Claude Code. "
                 + "Switching this off stops the reading; the permission macOS granted is macOS’s to "
                 + "withdraw, in Keychain Access.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.claudeLoginInKeychain { askAgain }
        }
    }

    /// For someone who chose Allow when they meant Always Allow.
    ///
    /// Allow works, which is exactly why it goes unnoticed: the numbers go live, and the
    /// dialog only returns the next time Brim opens or Claude Code renews its login. By
    /// then there was nothing on screen that could bring it back on purpose.
    private var askAgain: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button("Ask macOS Again") { store.askKeychainAgain() }
                .controlSize(.small)
            Text("Chose Allow instead of Always Allow? macOS will keep asking each time Brim opens. "
                 + "Press this and choose Always Allow. If you already did, no dialog appears.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checking: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Asking macOS for permission, then Anthropic for your usage…")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var offered: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("This reads the login Claude Code keeps on this Mac, which is the only credential "
                 + "here that Anthropic will answer usage for. Claude chat and Claude Design draw on the "
                 + "same allowance, so one login covers all three, but signing in to claude.ai does not "
                 + "leave one behind: Claude Code has to be installed and signed in once. There is "
                 + "nothing to paste. macOS will ask once whether Brim may read it — choose Always Allow.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Turn On Live Updates") { store.connect(.claudeCode) }
                    .buttonStyle(.borderedProminent)
                Text("Read-only. Your Claude Code session is never changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            skipNote
        }
    }

    /// The row this card opens under already carries what went wrong and the button
    /// that retries it. Saying both again here put the same sentence and the same
    /// button twice within an inch of each other; what is left is the part the row has
    /// no room for.
    private var problem: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.snapshot(.claudeCode) != nil {
                Text("Until the live read works, Brim keeps showing Claude Code’s cached reading with "
                     + "its true age, rather than a number it can’t stand behind.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.claudeKeychainRefused { keychainAccess }
            Text("A read that fails changes nothing at the other end. Brim only ever reads that login, "
                 + "so it cannot expire or invalidate it, and cannot sign you out of Claude Code.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            skipNote
        }
    }

    /// Try Again, on the row above, raises the dialog when macOS is still willing to
    /// show it. When it has remembered a refusal, the only place left to change that
    /// answer is Keychain Access, so this opens it rather than leaving the person to
    /// find an app macOS no longer puts anywhere obvious.
    private var keychainAccess: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button("Open Keychain Access") { Self.openKeychainAccess() }
                .controlSize(.small)
            Text("Press Try Again and choose Always Allow. If no dialog appears, find "
                 + "“Claude Code-credentials” in Keychain Access and add Brim on its Access Control tab.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func openKeychainAccess() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess")
        else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// What Sign In will do, said before it is pressed, because it installs something.
    private var signInOffer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Claude usage is read with Claude Code’s sign-in. The Claude app keeps its own "
                 + "sign-in private, so Brim can’t use that one. Sign In, above, sets this up for you: it "
                 + "installs Claude Code from Anthropic if it isn’t here yet, then opens claude.ai so you "
                 + "can sign in. You never need to open Terminal or Claude Code itself, and your password "
                 + "is only ever typed on claude.ai.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            skipNote
        }
    }

    private var skipNote: some View {
        Text("Skip it and Brim reads nothing from Claude at all, which is a perfectly good answer.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Installing and signing in, as it happens, with the two ways out of a stuck browser.
private struct ClaudeSetupProgress: View {
    @ObservedObject var store: UsageStore
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.claudeSetupStep {
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing Claude Code from Anthropic. This takes a minute the first time.")
                        .font(.callout)
                }
                cancel
            case .signingIn(let link):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Sign in on the claude.ai page that just opened in your browser. Brim carries on "
                         + "by itself when you’re done.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if link != nil {
                    Button("Browser didn’t open? Open the sign-in page") { store.openClaudeSignInLink() }
                        .buttonStyle(.link)
                }
                HStack(spacing: 8) {
                    TextField("If claude.ai shows you a code, paste it here", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button("Continue", action: send).disabled(code.isEmpty)
                }
                cancel
            case .failed(let message):
                Text(message)
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle:
                EmptyView()
            }
        }
    }

    private var cancel: some View {
        Button("Cancel") { store.cancelClaudeSetup() }.controlSize(.small)
    }

    private func send() {
        store.submitClaudeCode(code)
        code = ""
    }
}
