import AppKit
import SwiftUI
import BrimCore

/// The one-time approval that connecting a tool can produce, explained before it
/// happens rather than after.
///
/// Connecting hands off to the provider's own sign-in, and on this Mac that means
/// asking the keychain first. The buttons are the part worth recognising: the useful
/// one is not the default, so someone meeting the box cold presses Deny and concludes
/// the app is broken.
///
/// The panel is a replica, down to the wording, because someone who has never seen it
/// needs to recognise it on sight rather than read a description of it. One thing is
/// not a copy: the icon is Brim's, where the real locked prompt shows a gold padlock.
/// Brim's icon is what the *unlocked* prompt carries, and a house mark inside the house
/// window is worth more here than the last of the likeness. Nothing is
/// drawn over it: no ring, no arrow, no badge. An annotation painted on top would be
/// the one part of the picture that never appears on screen, and it is the likeness
/// that has to do the work. The captions underneath say which button to press, in
/// words.
///
/// Two things here were once decided the other way, and both were changed against a
/// real screenshot of the prompt on this Mac. Neither should be undone without one.
///
/// The section says out loud that this is Claude Code's box alone, because it is: see
/// `keychainItems` below.
///
/// It draws the *locked* keychain prompt, naming the item by name. macOS has two of
/// these: an unlocked login keychain gets an ACL prompt carrying the asking app's icon
/// and no password field, and a locked one gets this — the padlock, the item's name,
/// and a field for the login keychain password. An earlier version drew the unlocked
/// one with the item's name left out, so that one picture could stand for every
/// provider. It cost the reader the thing the picture is for: this is the box that
/// actually appears, worded as it actually appears.
///
/// The name revolves through `keychainItems`, which is every provider whose connection
/// really raises this box, each entry naming the keychain item the app really reads.
/// Today that is Claude Code alone, so the name sits still: Codex is read out of
/// `~/.codex/auth.json` and Perplexity out of its own preferences, and neither file
/// asks macOS for anything. Adding a provider here is one line, and putting one in that
/// does not use the keychain would draw a box that provider never shows.
///
/// It draws the password field, which an earlier version deliberately refused: a
/// picture of one, inside this app's window, risks teaching the reflex that a keychain
/// prompt exists to protect. The field is drawn empty and inert, and the caption says
/// whose box it is, because a reader who is shown a prompt without the field will meet
/// the real one and not recognise it — and not recognising it is the failure that
/// actually happens.
struct ConnectApprovalPreview: View {
    /// The tools actually found on this Mac, in the order the list above shows them.
    /// Only these are explained: a step for a tool that is not installed is a line
    /// about something the reader cannot do, on the one screen that should be short.
    var tools: [KnownTool]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            steps
            // The keychain box belongs to Claude Code alone. Without it installed
            // there is no prompt to recognise, and the picture would be a permission
            // request for a tool this Mac does not have.
            if tools.contains(.claudeCode) { figure }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    /// The same thing the rows say, for a reader who is not being shown them.
    private var spokenSummary: String {
        let lines = tools.map { "\($0.displayName). \(Self.whatHappens($0))" }
        guard tools.contains(.claudeCode) else { return lines.joined(separator: " ") }
        return lines.joined(separator: " ")
            + " The Claude Code box has three buttons. Press Always Allow, the leftmost "
            + "rather than the blue one. It is asked once and never again."
    }

    /// What switching each tool on actually does. Keyed off `KnownTool` rather than
    /// written as a list of its own, so a tool added to the app cannot quietly go
    /// unexplained here.
    ///
    /// Only Claude Code raises anything to approve, which is why the other two are
    /// still given a line: someone shown a permission box and nothing else assumes
    /// every tool brings one, and hesitates over the two that do not.
    private static func whatHappens(_ tool: KnownTool) -> String {
        switch tool {
        case .claudeCode:
            "macOS asks once, for the login Claude Code already keeps in your keychain. "
                + "Approve it and the numbers go live."
        case .codex:
            "Nothing to approve. Codex's own sign-in opens if you are not already signed "
                + "in to it, and Brim reads the shared Work allowance through that."
        case .perplexity:
            "Nothing to approve and nothing to sign in to. Brim reads the counts the "
                + "Perplexity app has already written to its own preferences."
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(tools) { tool in
                HStack(alignment: .top, spacing: 11) {
                    Group {
                        if let provider = tool.providers.first {
                            ProviderMark(provider: provider, size: 17, tint: .secondary)
                        }
                    }
                    .frame(width: 26, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.displayName).font(.callout)
                        Text(Self.whatHappens(tool))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The picture, captioned as Claude Code's alone so it cannot be read as the box
    /// all three raise.
    private var figure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("The box Claude Code's approval shows")
                .font(.callout)
                .foregroundStyle(.secondary)
            dialog
            captions
        }
    }

    /// The keychain item each provider's connection asks for, in the order they are
    /// shown. One entry means a still picture rather than a revolving one, which is
    /// correct: a name that revolved through providers that never raise this box would
    /// be telling the reader about a prompt they will never see.
    private static let keychainItems: [String] = [ClaudeCredential.servicePrefix]

    /// How long each name is left up. Long enough to read the whole line it sits in,
    /// which is the only thing the timing has to be good for.
    private static let dwell: TimeInterval = 3.4

    @State private var shown = 0
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var item: String { Self.keychainItems[shown % Self.keychainItems.count] }

    private var dialog: some View {
        AlertPanel(icon: AnyView(AppIconImage(size: 64)),
                   message: "Brim wants to access key \"\(item)\" in your keychain.",
                   informativeText: "To allow this, enter the \"login\" keychain password.",
                   accessory: AnyView(PasswordFieldSketch()),
                   actions: [.init(title: "Always Allow", separated: true),
                             .init(title: "Deny"),
                             .init(title: "Allow", isDefault: true)],
                   showsHelpButton: true)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: shown)
            .task { await revolve() }
    }

    /// Left as a plain sleep loop rather than a `Timer`: the task is cancelled with the
    /// view, so a first-run screen that has been dismissed stops waking the app up.
    /// A single name never starts the loop at all.
    private func revolve() async {
        guard Self.keychainItems.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.dwell))
            guard !Task.isCancelled else { return }
            shown += 1
        }
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 9) {
            caption("checkmark.circle.fill", Palette.positive) {
                Text("Press ") + Text("Always Allow").bold()
                    + Text(" \u{2014} the button on the left, not the blue one. You are asked once, "
                           + "and never again. Deny is safe too: nothing else stops working, and "
                           + "the tool simply stays switched off.")
            }
        }
    }

    private func caption(_ symbol: String, _ tint: Color,
                         @ViewBuilder text: () -> Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(tint)
            text()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The password row the locked prompt puts under its text: a label, a field, and the
/// focus ring macOS leaves on it because the field is where the caret starts.
///
/// Empty, and not a `TextField`. A real one would take focus away from the window it is
/// drawn in and offer to accept typing, and this is a picture. `AlertPanel` refuses
/// clicks for the whole panel, so nothing here can be typed into.
struct PasswordFieldSketch: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Password:")
                .font(.system(size: 13))
                .foregroundStyle(Palette.text)
            let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
            shape.fill(Color(nsColor: .textBackgroundColor))
                .overlay(shape.strokeBorder(Palette.accent, lineWidth: 1))
                .overlay(shape.strokeBorder(Palette.accent.opacity(0.4), lineWidth: 3).padding(-2))
                .frame(height: 22)
        }
        .padding(.trailing, 2)
    }
}

/// The running app's icon, which is what macOS puts in a prompt raised on its behalf.
///
/// Read from the bundle rather than drawn, so it stays the app's real icon through
/// every redesign of it.
///
/// The bundle's own resource rather than `NSApp.applicationIconImage`, which is the
/// same picture in a real app but hands back a generic blue folder when there is no
/// bundle to read: running `swift run`, a unit test host, or the `--render-welcome`
/// screenshot. A folder in the middle of the illustration is worse than the drawn mark,
/// so `BrandMark` takes over instead.
struct AppIconImage: View {
    var size: CGFloat = 64
    var body: some View {
        if let icon = Bundle.main.image(forResource: "AppIcon") {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            BrandMark(size: size)
        }
    }
}
