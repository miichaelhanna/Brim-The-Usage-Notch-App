import SwiftUI

/// The providers' own marks.
///
/// Outlines come from Simple Icons (https://simpleicons.org), which publishes brand
/// icons under CC0. The icons themselves remain the trademarks of their owners and are
/// not covered by this project's MIT licence, see LICENSE. The Claude ring uses the
/// Claude Code character instead, in `Mascot.swift`, drawn through the same reader.
///
/// The source SVGs use elliptical arcs, which a path reader would otherwise have to
/// implement. They were converted once, offline, into lines and cubic curves only, so
/// the reader below stays small enough to audit at a glance. Coordinates are in the
/// icons' original 24×24 space and scaled to fit.
enum BrandMarks {
    /// Reads the reduced subset the conversion emits: absolute move, line, cubic and
    /// close. Anything else is ignored rather than guessed at.
    static func path(_ data: String, in rect: CGRect, viewBox: CGFloat = 24) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"

        for token in data.split(separator: " ") {
            if let first = token.first, first.isLetter {
                command = first
                numbers.removeAll()
                if command == "Z" { path.closeSubpath() }
                continue
            }
            guard let value = Double(token) else { continue }
            numbers.append(CGFloat(value))
            switch command {
            case "M" where numbers.count == 2:
                path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "L" where numbers.count == 2:
                path.addLine(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "C" where numbers.count == 6:
                path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]),
                              control1: CGPoint(x: numbers[0], y: numbers[1]),
                              control2: CGPoint(x: numbers[2], y: numbers[3]))
            default:
                continue
            }
            numbers.removeAll()
        }

        let scale = min(rect.width, rect.height) / viewBox
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                               tx: rect.minX + (rect.width - viewBox * scale) / 2,
                                               ty: rect.minY + (rect.height - viewBox * scale) / 2))
    }

    /// Outline of the openai mark, reduced to lines and cubics.
    static let openai = "M 22.2819 9.8211 C 22.8248 8.1862 22.6369 6.3967 21.7662 4.9103 C 20.4571 2.6316 17.826 1.4595 15.2564 2.0103 C 13.8083 0.3995 11.6112 -0.3168 9.492 0.1311 C 7.3728 0.5789 5.6533 2.1229 4.9807 4.1818 C 3.2928 4.5279 1.836 5.5847 0.983 7.0818 C -0.3404 9.3568 -0.0401 12.2267 1.7257 14.1784 C 1.1808 15.8125 1.367 17.6022 2.2367 19.0891 C 3.5475 21.3686 6.1803 22.5406 8.7513 21.9892 C 9.8948 23.277 11.5377 24.0097 13.2599 24 C 15.8937 24.0024 18.2271 22.3021 19.0317 19.7942 C 20.7194 19.4475 22.176 18.3908 23.0294 16.8941 C 24.3368 14.6231 24.0351 11.7688 22.2819 9.8212 Z M 13.2599 22.4292 C 12.2086 22.4309 11.1903 22.0624 10.3835 21.3884 L 10.5254 21.308 L 15.3037 18.5498 C 15.5456 18.4079 15.6949 18.149 15.6964 17.8685 L 15.6964 11.1316 L 17.7164 12.3002 C 17.7367 12.3105 17.7508 12.3298 17.7544 12.3522 L 17.7544 17.9348 C 17.7491 20.4148 15.7399 22.424 13.2599 22.4292 Z M 3.5992 18.3038 C 3.072 17.3934 2.8827 16.3263 3.0646 15.2901 L 3.2066 15.3753 L 7.9896 18.1335 C 8.2306 18.2749 8.5292 18.2749 8.7702 18.1335 L 14.613 14.765 L 14.613 17.0974 C 14.6119 17.1219 14.5997 17.1445 14.5798 17.1589 L 9.74 19.9502 C 7.5893 21.1891 4.8416 20.4525 3.5992 18.3038 Z M 2.3408 7.8956 C 2.8717 6.9794 3.7096 6.2805 4.7063 5.9228 L 4.7063 11.6 C 4.7026 11.8793 4.8513 12.1386 5.0942 12.2765 L 10.9086 15.6308 L 8.8885 16.7993 C 8.8663 16.8111 8.8397 16.8111 8.8175 16.7993 L 3.9872 14.0128 C 1.8408 12.7686 1.1047 10.023 2.3408 7.872 Z M 18.9371 11.7514 L 13.1038 8.364 L 15.1192 7.2 C 15.1414 7.1882 15.168 7.1882 15.1902 7.2 L 20.0205 9.9913 C 21.5281 10.8612 22.3979 12.5234 22.2531 14.258 C 22.1083 15.9926 20.975 17.4876 19.344 18.0955 L 19.344 12.4183 C 19.3355 12.1397 19.1808 11.8863 18.937 11.7513 Z M 20.9478 8.7283 L 20.8058 8.6431 L 16.0323 5.8613 C 15.7898 5.719 15.4894 5.719 15.2469 5.8613 L 9.409 9.2297 L 9.409 6.8974 C 9.4065 6.8732 9.4174 6.8496 9.4374 6.8359 L 14.2677 4.0493 C 15.779 3.1787 17.6573 3.2599 19.0877 4.2578 C 20.5182 5.2556 21.2431 6.9903 20.9479 8.7093 Z M 8.3065 12.863 L 6.2865 11.6992 C 6.266 11.6869 6.2521 11.6661 6.2485 11.6425 L 6.2485 6.0742 C 6.2508 4.3304 7.2605 2.7449 8.8397 2.0054 C 10.419 1.2659 12.2833 1.5056 13.6242 2.6205 L 13.4822 2.701 L 8.704 5.459 C 8.4621 5.6009 8.3128 5.8598 8.3113 6.1403 Z M 9.4041 10.4976 L 12.0061 8.9978 L 14.613 10.4976 L 14.613 13.497 L 12.0156 14.9967 L 9.4089 13.497 Z"

    /// Outline of the perplexity mark, reduced to lines and cubics.
    static let perplexity = "M 22.3977 7.0896 L 20.0871 7.0896 L 20.0871 0.0676 L 12.5777 6.4218 L 12.5777 0.1577 L 11.4223 0.1577 L 11.4223 6.3543 L 4.4904 0 L 4.4904 7.0896 L 1.6023 7.0896 L 1.6023 17.4872 L 4.4905 17.4872 L 4.4905 24 L 11.4225 17.6409 L 11.4225 23.8414 L 12.5779 23.8414 L 12.5779 17.7945 L 19.5097 23.9752 L 19.5097 17.4873 L 22.3979 17.4873 L 22.3979 7.0896 Z M 18.932 2.5586 L 18.932 7.0896 L 13.577 7.0896 L 18.932 2.5586 Z M 5.6458 2.6262 L 10.5149 7.0896 L 5.6458 7.0896 L 5.6458 2.6262 Z M 2.7576 16.332 L 2.7576 8.245 L 10.6052 8.245 L 4.4903 14.3597 L 4.4903 16.332 L 2.7576 16.332 Z M 5.6458 21.3724 L 5.6458 17.4872 L 5.6459 17.4872 L 5.6459 14.8384 L 11.4222 9.062 L 11.4222 16.0731 L 5.6458 21.3724 Z M 18.3544 21.3972 L 12.5778 16.2463 L 12.5778 9.0618 L 18.3544 14.8384 L 18.3544 21.3972 Z M 21.2426 16.332 L 19.5096 16.332 L 19.5096 14.3597 L 13.3948 8.245 L 21.2426 8.245 L 21.2426 16.332 Z"

    /// Outline of the Cursor mark, from cursor.com/brand, reduced to lines and cubics.
    /// Two subpaths, the cube and the wedge cut out of it, so fill it even-odd.
    static let cursor = "M 22.069 5.704 L 12.497 0.178 C 12.189 0 11.81 0 11.503 0.178 L 1.931 5.704 C 1.672 5.853 1.513 6.129 1.513 6.428 L 1.513 17.572 C 1.513 17.871 1.672 18.147 1.931 18.296 L 11.503 23.822 C 11.81 24 12.19 24 12.497 23.822 L 22.069 18.296 C 22.328 18.147 22.487 17.871 22.487 17.572 L 22.487 6.428 C 22.487 6.129 22.328 5.853 22.069 5.704 L 22.069 5.704 Z M 21.468 6.875 L 12.227 22.88 C 12.164 22.988 12 22.943 12 22.819 L 12 12.339 C 12 12.129 11.888 11.935 11.706 11.83 L 2.63 6.591 C 2.523 6.528 2.567 6.363 2.692 6.363 L 21.173 6.363 C 21.435 6.363 21.599 6.648 21.468 6.875 L 21.468 6.875 L 21.468 6.875 Z"

    /// The Figma symbol as Mike drew it: five outlined lobes rather than five filled
    /// colours, so it tints like every other mark here instead of carrying its own
    /// palette. Converted from a 172x247 source into this file's 24x24 space.
    static let figma = [
        "M 19.579 4.518 C 19.579 6.584 17.904 8.259 15.838 8.259 L 12.0 8.259 L 12.0 0.777 L 15.838 0.777 C 17.904 0.777 19.579 2.452 19.579 4.518 L 19.579 4.518 Z",
        "M 4.421 4.518 C 4.421 6.584 6.096 8.259 8.162 8.259 L 12.0 8.259 L 12.0 0.777 L 8.162 0.777 C 6.096 0.777 4.421 2.452 4.421 4.518 L 4.421 4.518 Z",
        "M 4.421 12.0 C 4.421 14.066 6.096 15.741 8.162 15.741 L 12.0 15.741 L 12.0 8.259 L 8.162 8.259 C 6.096 8.259 4.421 9.934 4.421 12.0 L 4.421 12.0 Z",
        "M 4.421 19.482 C 4.421 21.548 6.12 23.223 8.186 23.223 L 8.186 23.223 C 10.279 23.223 12.0 21.526 12.0 19.433 L 12.0 15.741 L 8.162 15.741 C 6.096 15.741 4.421 17.416 4.421 19.482 L 4.421 19.482 Z",
        "M 12.0 12.0 C 12.0 14.066 13.675 15.741 15.741 15.741 L 15.838 15.741 C 17.904 15.741 19.579 14.066 19.579 12.0 L 19.579 12.0 C 19.579 9.934 17.904 8.259 15.838 8.259 L 15.741 8.259 C 13.675 8.259 12.0 9.934 12.0 12.0 L 12.0 12.0 Z"
    ]

    /// The stroke the Figma symbol is drawn with, in the same 24x24 space.
    static let figmaStroke: CGFloat = 1.4654
}

/// A brand outline, drawn from `BrandMarks`.
struct BrandGlyph: Shape {
    let data: String
    func path(in rect: CGRect) -> Path { BrandMarks.path(data, in: rect) }
}

/// The Figma symbol: five outlined lobes, stroked in the current tint.
struct FigmaMark: View {
    var size: CGFloat = 20
    var tint: Color = .primary
    var body: some View {
        ZStack {
            ForEach(Array(BrandMarks.figma.enumerated()), id: \.offset) { _, part in
                BrandGlyph(data: part)
                    .stroke(tint, style: StrokeStyle(lineWidth: BrandMarks.figmaStroke * size / 24,
                                                     lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
