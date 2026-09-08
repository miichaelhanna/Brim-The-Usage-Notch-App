import SwiftUI
import BrimCore

/// The one-time approval that connecting anything can produce, explained before it
/// happens rather than after.
///
/// Every provider hands off to its own sign-in, and some of those ask your Mac for
/// permission first. The buttons are the part worth recognising: the useful one is not
/// the default, so someone meeting the box cold presses Deny and concludes the app is
/// broken.
///
/// Deliberately provider-agnostic. An explanation that named Claude Code would have to
/// be written again for ChatGPT and again for whatever comes next, and would be wrong
/// on the first run of a Mac that has neither.
///
/// The panel is drawn at its real size and proportions, because someone who has never
/// seen it needs to recognise it on sight, not read a description of it. There is no
/// password field, because the real prompt has none either: the keychain is already
/// unlocked and the only question is whether this app may read one item in it. Anything
/// that taught someone to type a password into a drawing of a system panel would be
/// worse than no picture at all.
struct ConnectApprovalPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            journey
            dialog
            caption
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connecting a tool may ask your Mac for permission once. "
                            + "Choose Always Allow. It is asked once and never again.")
    }

    // MARK: What happens, in three steps

    private var journey: some View {
        HStack(spacing: 8) {
            step("switch.2", "You switch a tool on")
            arrow
            step("checkmark.shield.fill", "Approve it once", highlighted: true)
            arrow
            step("chart.bar.fill", "Numbers go live")
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func step(_ symbol: String, _ title: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(highlighted ? Palette.accent : Color.secondary)
                .frame(width: 27, height: 27)
                .background(
                    Circle().fill(highlighted ? Palette.accent.opacity(0.13) : Color.secondary.opacity(0.09))
                )
            Text(title)
                .font(.caption2)
                .foregroundStyle(highlighted ? Palette.text : Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: The panel itself

    /// The wording is the system's own, with the keychain item's name left out: that
    /// name differs per provider, and naming one would make the picture wrong for
    /// every other tool.
    private var dialog: some View {
        AlertPanel(icon: AnyView(BrandMark(size: 64)),
                   message: "Brim wants to use your confidential information stored in your keychain.",
                   informativeText: "Do you want to allow access to this item?",
                   actions: [.init(title: "Always Allow", recommended: true),
                             .init(title: "Deny"),
                             .init(title: "Allow", isDefault: true)])
            .frame(maxWidth: .infinity)
    }

    private var caption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Palette.positive)
            (Text("Pick ") + Text("Always Allow").bold()
                + Text(", the one ringed in green. You are asked once, and never again. Deny is "
                       + "safe too: nothing else stops working, and the tool simply stays "
                       + "switched off."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
