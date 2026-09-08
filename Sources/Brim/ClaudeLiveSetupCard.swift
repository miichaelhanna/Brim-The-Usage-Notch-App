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
            switch store.liveClaude {
            case .on: connected
            case .checking: checking
            case .off: offered
            case .problem(let message): problem(message)
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
            Text("Brim reads the login Claude Code already keeps on this Mac, and only reads it. It "
                 + "cannot expire, rotate or invalidate that login, so it cannot sign you out of Claude Code. "
                 + "Switching this off stops the reading; the permission macOS granted is macOS’s to "
                 + "withdraw, in Keychain Access.")
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
            Text("There is nothing to paste and no second login. macOS will ask once whether Brim may "
                 + "read that saved login. Choose Always Allow and the numbers go live.")
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

    private func problem(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { store.connect(.claudeCode) }.buttonStyle(.borderedProminent)
            skipNote
        }
    }

    private var skipNote: some View {
        Text("Skip it and Brim reads nothing from Claude at all, which is a perfectly good answer.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
