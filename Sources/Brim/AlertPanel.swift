import SwiftUI
import BrimCore

/// A drawing of a macOS alert, in the shape `NSAlert` gives one.
///
/// Not a working alert and not a wrapper around one: a picture of the thing, for
/// showing someone what is about to appear on their screen. Real alerts cannot be
/// embedded in a view, and a screenshot of one ages with every macOS release and ships
/// at one appearance and one accent colour. This follows the Mac it is drawn on.
///
/// The anatomy is the Mac's: the icon on the left, the bold message and its lighter
/// informative line to the right of it, and the buttons in a row along the bottom with
/// the default one rightmost. Wide rather than tall.
///
/// Not the centred column with full-width stacked buttons. That shape belongs to iOS,
/// and a Mac app that draws it looks like a phone app someone has resized.
///
/// The metrics below are matched by eye against alerts on this OS, not taken from a
/// published spec, because Apple documents alert anatomy but not its measurements. If
/// a real one is ever measured properly, this is the single place to correct.
struct AlertPanel: View {
    struct Action: Identifiable {
        let id = UUID()
        var title: String
        /// The one macOS fills with the accent colour and triggers on Return.
        var isDefault = false
        /// Ours, not Apple's. Marks the button this app is pointing the reader at, in
        /// a colour the alert itself never uses so the two cannot be confused.
        var recommended = false
    }

    /// The app whose alert this is. `NSAlert` shows the running app's icon.
    var icon: AnyView
    var message: String
    var informativeText: String?
    var actions: [Action]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                icon.frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                // The default sits rightmost, wherever it was handed to us.
                ForEach(actions.sorted { !$0.isDefault && $1.isDefault }) { button($0) }
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.background)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.5)
        )
        // A drawing, not an alert. A click lands on whatever is behind it.
        .allowsHitTesting(false)
    }

    private func button(_ action: Action) -> some View {
        Text(action.title)
            .font(.system(size: 13))
            .foregroundStyle(action.isDefault ? Color.white : Palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(action.isDefault ? Palette.accent : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(action.isDefault ? .clear : Palette.line, lineWidth: 0.5)
            )
            .overlay {
                if action.recommended {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Palette.positive, lineWidth: 2.5)
                        .padding(-4)
                }
            }
    }
}
