import AppKit
import SwiftUI
import BrimCore

struct ProviderMark: View {
    let provider: Provider
    var size: CGFloat = 26
    var tint: Color = Palette.text

    /// The Claude character is wider than it is tall. Fitted into the same square as
    /// the round marks it read visibly smaller than them, so it gets a wider frame and
    /// is drawn to fill it: the same height as its neighbours, and its own width.
    static func width(of provider: Provider, size: CGFloat) -> CGFloat {
        provider.displayProvider == .claude ? size * 1.4 : size
    }

    var body: some View {
        Group {
            switch provider {
            case .claude, .claudeCode:
                // The Claude Code character stands for the whole Claude allowance:
                // of Anthropic's marks it is the one people who watch these limits
                // actually recognise.
                ClaudeMascotGlyph().fill(tint, style: FillStyle(eoFill: true))
            case .chatgpt:
                BrandGlyph(data: BrandMarks.openai).fill(tint)
            case .codex:
                CodexMark().fill(tint, style: FillStyle(eoFill: true))
            }
        }.frame(width: Self.width(of: provider, size: size), height: size).accessibilityHidden(true)
    }
}

/// A tool's mark. Built-in providers have their own; a tool someone described has
/// initials, which are honestly initials rather than an invented logo.
struct ToolMark: View {
    let tool: TrackedTool
    var size: CGFloat = 26
    var tint: Color = Palette.text
    var body: some View {
        Group {
            if let provider = tool.builtin {
                ProviderMark(provider: provider, size: size, tint: tint)
            } else {
                Text(tool.monogram)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.3)
                        .stroke(tint.opacity(0.4), lineWidth: max(1, size * 0.045)))
            }
        }.accessibilityHidden(true)
    }
}

/// A notch hanging from the top edge of its rect: square shoulders where it meets the
/// edge, rounded where it ends. The app's mark in every size it is drawn at: the icon,
/// the menu bar and the first-run header, so the three cannot drift apart.
struct HangingNotchShape: Shape {
    /// Corner radius as a fraction of the shape's height, from the design file: 72/205.
    var cornerFraction: CGFloat = 72 / 205
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height * cornerFraction, rect.width / 2)
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
            .path(in: rect)
    }
}

/// The app's mark: a black tile with a white notch hanging from its top edge, mirroring
/// the app icon. Proportions come from the 1024 design grid, where the notch is half the
/// tile's width and a fifth of its height.
///
/// Not the mascot. The Claude Code character is Anthropic's mark; the app's own mark is
/// its own shape, so the two are not confused and no borrowed logo stands in for Brim.
struct BrandMark: View {
    var size: CGFloat = 30
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size * 229 / 1024).fill(Color.black)
            HangingNotchShape()
                .fill(Color.white)
                .frame(width: size * 0.5, height: size * 205 / 1024)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct UsageRing: View {
    let tool: TrackedTool
    var percent: Double?
    var size: CGFloat = 58
    var subdued = false
    var severity: UsageSeverity = .normal
    var surface: Surface = .app
    /// A reading is being fetched for this tool right now.
    var busy = false
    @State private var spun = false
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var body: some View {
        ZStack {
            Circle().stroke(surface.track, lineWidth: size * 0.065)
            if let percent {
                Circle().trim(from: 0, to: max(0, min(percent, 100)) / 100)
                    .stroke(surface.usage(percent, severity: severity),
                            style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: percent)
            }
            // Fetching a reading takes as long as the provider takes, seconds even, for
            // one that has to be woken up first. The click has to say so immediately
            // or it reads as a dead control, so the arc appears on the press rather
            // than when the answer lands.
            if busy {
                Circle().trim(from: 0, to: 0.16)
                    .stroke(surface.text.opacity(0.85),
                            style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
                    .rotationEffect(.degrees(spun ? 360 : 0))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) { spun = true }
                    }
                    .onDisappear { spun = false }
            }
            ToolMark(tool: tool, size: size * 0.46, tint: surface.text)
                .opacity(percent == nil ? 0.55 : 1)
        }.frame(width: size, height: size).opacity(subdued ? 0.55 : 1)
            .animation(.easeOut(duration: 0.15), value: busy)
    }
}

/// A small caps chip. Marks a row's status without competing with the number.
struct StatusFlag: View {
    let text: String
    var color: Color = Palette.muted
    var body: some View {
        Text(text).font(.system(size: 8, weight: .semibold)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(text.lowercased())
    }
}

/// One usage window. The limiting window is drawn `emphasised` and lifted onto its
/// own panel so the eye lands on the limit that actually applies, rather than on
/// whichever row happens to be first.
struct UsageBar: View {
    let window: UsageWindow
    let now: Date
    var emphasised = false
    var surface: Surface = .app
    var body: some View {
        let expired = window.hasExpired(at: now)
        let tint = surface.usage(window.usedPercent, severity: window.severity)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(window.title).font(.system(size: emphasised ? 14 : 13, weight: .medium))
                if window.isActive { StatusFlag(text: "LIMITING", color: tint) }
                if window.isEstimated { StatusFlag(text: "ESTIMATED", color: surface.muted) }
                Spacer(minLength: 8)
                Text(window.resetDescription(at: now)).font(.system(size: 11)).foregroundStyle(surface.muted)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(surface.track)
                    Capsule().fill(tint).frame(width: max(0, geometry.size.width * window.fraction))
                }
            }.frame(height: emphasised ? 8 : 6)
            HStack {
                Text("\(Int(window.usedPercent.rounded()))% used").foregroundStyle(expired ? surface.muted : surface.text)
                Spacer()
                if !expired { Text("\(Int(max(0, 100 - window.usedPercent).rounded()))% left").foregroundStyle(surface.muted) }
            }.font(.system(size: 11)).monospacedDigit()
        }
        .opacity(expired ? 0.5 : 1)
        .padding(emphasised ? 13 : 0)
        .background {
            if emphasised {
                RoundedRectangle(cornerRadius: 12).fill(tint.opacity(surface == .app ? 0.06 : 0.10))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.28), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.title), \(Int(window.usedPercent.rounded())) percent used"
                            + (window.isActive ? ", currently limiting" : "")
                            + (window.isEstimated ? ", estimated" : ""))
    }
}

struct QuietButton: ButtonStyle {
    var prominent = false
    var surface: Surface = .app
    func makeBody(configuration: Configuration) -> some View {
        let quietFill = surface == .app
            ? Color.black.opacity(configuration.isPressed ? 0.10 : 0.05)
            : Color.white.opacity(configuration.isPressed ? 0.12 : 0.065)
        return configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.white : surface.text.opacity(0.9))
            .background(prominent ? surface.accent : quietFill, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension View {
    func card(padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line, lineWidth: 1))
            // A soft lift, so white cards separate from a white-ish page.
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 2)
    }
}
