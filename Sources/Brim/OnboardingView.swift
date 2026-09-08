import AppKit
import SwiftUI
import BrimCore

/// First run. Its job is to show what is on this Mac, and to be the place each tool is
/// connected from, one switch at a time.
///
/// Nothing has been read when this appears: detection looks for files, not accounts, so
/// every row starts at "not connected" and says so. It used to label anything it found
/// "Ready", which claimed a sign-in it had never checked, and it offered no way to
/// connect ChatGPT at all. People are right to be wary of an app that reads AI account
/// data, and the answer is that it reads none of it until asked, per tool.
///
/// The switches are the same ones Connections uses, so the two screens cannot disagree,
/// and neither can reach an account without a click. They are not the notch's
/// visibility switches, which only hide a ring: these start and stop the reading.
///
/// Laid out like a macOS welcome pane: centred, generous, with the action pinned to the
/// bottom bar so it is never below the fold.
struct OnboardingView: View {
    @ObservedObject var store: UsageStore
    var finish: () -> Void

    private var found: [KnownTool] { KnownTool.installed }
    /// The one line the whole screen has to earn: what has actually been read so far.
    private var nothingReadYet: Bool { store.connectedTools.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { content }
            Divider()
            bottomBar
        }
        .background(Palette.background)
    }

    /// The same screen with the scroll view taken off, for `--render-welcome`.
    /// `ImageRenderer` draws a `ScrollView` as an empty box, so a render of `body`
    /// comes back as a bottom bar and nothing else.
    var flattened: some View {
        VStack(spacing: 0) {
            content
            Divider()
            bottomBar
        }
        .background(Palette.background)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            if found.isEmpty { nothingFound } else { foundSection }
            if !found.isEmpty { approvalSection }
            footnote
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 44)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Text(summary)
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button(found.isEmpty ? "Continue Anyway" : "Start Using Brim", action: finish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(.bar)
    }

    /// Counts what is actually connected, not what is merely installed. The two are
    /// only the same for someone already signed in to everything they have.
    private var summary: String {
        guard !found.isEmpty else { return "Install a supported tool and it appears here automatically." }
        let states = found.map { $0.connection(in: store) }
        if states.contains(where: { $0.status == .checking }) { return "Checking what’s signed in on this Mac…" }
        let ready = states.filter(\.isConnected).count
        guard ready < found.count else {
            return "^[\(ready) tool](inflect: true) connected. Everything is changeable later."
        }
        return "\(ready) of \(found.count) connected. The rest can be finished here or in Connections."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandMark(size: 52)
            VStack(alignment: .leading, spacing: 7) {
                Text("Your AI limits, in one place")
                    .font(.system(size: 28, weight: .semibold))
                Text("Brim reads what the tools you already use have saved on this Mac. No API keys, no "
                     + "second login, nothing leaves your machine, and nothing is read until you connect it.")
                    .font(.title3).fontWeight(.regular).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var foundSection: some View {
        section(nothingReadYet ? "Found on this Mac, not read yet" : "Found on this Mac") {
            VStack(spacing: 0) {
                ForEach(Array(found.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 { Divider().padding(.leading, 34) }
                    toolRow(tool)
                }
            }
        }
    }

    /// A titled card. The app's own `card()` rather than `GroupBox`, so first run is
    /// made of the same surfaces as the rest of the window instead of borrowing a
    /// control that only appears here.
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 17)
        }
    }

    private var nothingFound: some View {
        section("Nothing found yet") {
            Text("None of the supported tools are installed. Install Claude Code or the ChatGPT "
                 + "desktop app and Brim picks them up automatically. There is no setup step to "
                 + "come back for.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var approvalSection: some View {
        section("What happens when you switch one on") {
            ConnectApprovalPreview(tools: found)
        }
    }

    private var footnote: some View {
        Text("Using something else? Brim connects only to tools it can read, and it is open source. "
             + "A tool that saves its usage to a file can be added in Connections, with no code and "
             + "no figures typed in by hand.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toolRow(_ tool: KnownTool) -> some View {
        let state = tool.connection(in: store)
        return HStack(spacing: 11) {
            Group {
                if let provider = tool.providers.first {
                    ProviderMark(provider: provider, size: 19, tint: .primary)
                } else {
                    SettingsIcon(symbol: "puzzlepiece.extension.fill", tint: .gray, size: 19)
                }
            }.frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(state.isProblem ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            switch state.status {
            case .checking: ProgressView().controlSize(.small)
            case .needsSignIn: Button("Sign In") { store.connect(tool) }
            case .problem: Button("Try Again") { store.connect(tool) }
            // The switch says what will happen; the tick says it already has. Without
            // it, on and off differ only by the position of a small grey control.
            case .connected: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .off: EmptyView()
            }
            Toggle("Connected", isOn: connection(tool))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .accessibilityLabel("Connect \(tool.displayName)")
        }
        .padding(.vertical, 9)
    }

    /// The same switch Connections has, so nobody has to find that screen to connect
    /// something this one has just told them is not connected.
    private func connection(_ tool: KnownTool) -> Binding<Bool> {
        Binding(get: { store.isConnected(tool) },
                set: { $0 ? store.connect(tool) : store.disconnect(tool) })
    }
}
