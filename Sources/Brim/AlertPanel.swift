import AppKit
import SwiftUI
import BrimCore

/// A drawing of a macOS alert, in the shape `NSAlert` gives one.
///
/// Not a working alert and not a wrapper around one: a picture of the thing, for
/// showing someone what is about to appear on their screen. Real alerts cannot be
/// embedded in a view, and a screenshot of one ages with every macOS release and ships
/// at one appearance and one accent colour. This follows the Mac it is drawn on.
///
/// The anatomy is the wide one: the icon on the left, the bold message and its lighter
/// informative line to the right of it, and the buttons in a row along the bottom with
/// the default one rightmost.
///
/// That is deliberately *not* the shape `NSAlert` makes any more. A modern `NSAlert` is
/// a narrow 260pt column with the icon above the text and full-width buttons stacked
/// under it. The prompt this app is explaining does not come from `NSAlert`: a keychain
/// prompt is drawn by the system's own security agent, which still uses the wide
/// layout. Drawing the `NSAlert` shape here would be a faithful copy of the wrong box.
///
/// The metrics are measured rather than guessed. They come from a real `NSAlert` built
/// on this OS and dumped view by view, which is the only part of the system that will
/// hand over its own numbers: 20pt margins, a 64pt icon, 16pt from icon to text, 13pt
/// bold message, 10pt down to the informative line, 16pt down to the buttons, and
/// buttons 28pt tall. The security agent's panel matches those to the eye.
///
/// One number is not `NSAlert`'s. It sets the informative line at 13pt regular now,
/// matching the message; the security agent still draws it at the classic 11pt, and
/// that is the panel being copied. Re-measure by hand if a future macOS moves either.
struct AlertPanel: View {
    struct Action: Identifiable {
        let id = UUID()
        var title: String
        /// The one macOS fills with the accent colour and triggers on Return.
        var isDefault = false
        /// macOS sets the third button apart from the default and its neighbour, so
        /// the pair that answers the question reads as a pair. The gap is part of how
        /// the box looks, and the button being set apart here is the one to press.
        var separated = false
    }

    /// The picture at the left. An `NSAlert` shows the asking app's icon; the keychain
    /// prompt this draws shows a padlock instead.
    var icon: AnyView
    var message: String
    var informativeText: String?
    /// Whatever the panel puts under its text before the buttons: the keychain prompt's
    /// password row, on the variant that has one. Alerts that are only text pass none.
    var accessory: AnyView?
    var actions: [Action]
    /// The small `?` at the bottom left, opposite the buttons. Off by default: a plain
    /// `NSAlert` has none, and only a panel wired to a help book shows one.
    var showsHelpButton = false

    private let margin: CGFloat = 20
    private let buttonHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                icon.frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let informativeText {
                        Text(informativeText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let accessory { accessory.padding(.top, 4) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 0) {
                if showsHelpButton { helpButton }
                Spacer(minLength: 12)
                // The default sits rightmost, wherever it was handed to us.
                let ordered = actions.sorted { !$0.isDefault && $1.isDefault }
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, action in
                    button(action)
                    if index < ordered.count - 1 {
                        Spacer().frame(width: action.separated ? 24 : 12)
                    }
                }
            }
        }
        .padding(margin)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.background)
                .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.5)
        )
        // A drawing, not an alert. A click lands on whatever is behind it.
        .allowsHitTesting(false)
    }

    /// A plain button's fill is `controlColor`, which is what the real ones use. On a
    /// dark Mac that is translucent white and reads on its own; on a light one it is
    /// white on a white panel, so the edge and the hairline shadow are the only things
    /// holding the button's shape. Both are drawn in both appearances, as macOS does.
    private static let controlEdge = Palette.adaptive(light: NSColor.black.withAlphaComponent(0.16),
                                                      dark: NSColor.white.withAlphaComponent(0.07))

    private func control<S: InsettableShape>(_ shape: S) -> some View {
        shape.fill(Color(nsColor: .controlColor))
            .overlay(shape.strokeBorder(Self.controlEdge, lineWidth: 0.5))
            .compositingGroup()
            .shadow(color: .black.opacity(0.10), radius: 0.5, y: 0.5)
    }

    private var helpButton: some View {
        Text("?")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: buttonHeight, height: buttonHeight)
            .background(control(Circle()))
    }

    private func button(_ action: Action) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Text(action.title)
            .font(.system(size: 13))
            .foregroundStyle(action.isDefault ? Color.white : Palette.text)
            .padding(.horizontal, 14)
            .frame(height: buttonHeight)
            .frame(minWidth: 74)
            .background {
                if action.isDefault {
                    shape.fill(Palette.accent)
                        .shadow(color: .black.opacity(0.10), radius: 0.5, y: 0.5)
                } else {
                    control(shape)
                }
            }
    }
}
