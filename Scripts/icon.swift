import AppKit

// The app's mark: a black tile with a white notch hanging from its top edge. Drawn from
// the same numbers as Resources/Mark/brim-appicon-1024.svg, in a 1024 space, so the
// exported icon and the design file cannot drift apart.
//
// The notch is the app, so the notch is the icon. It hangs from the top rather than
// sitting on an edge because that is where a MacBook's own notch is, and it is white on
// black rather than black on white because at 16pt a thin black shape on a white tile
// disappears into whatever is behind it.

let markWidth: CGFloat = 512      // 256…768 in the 1024 grid
let markHeight: CGFloat = 205
let markCornerRadius: CGFloat = 72
let tileCornerRadius: CGFloat = 229

/// The notch, in a y-up 1024 space: a rectangle hanging from the top edge whose two
/// bottom corners are rounded.
func notchPath() -> CGPath {
    let left: CGFloat = (1024 - markWidth) / 2
    let right = left + markWidth
    let bottom = 1024 - markHeight
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: 1024))
    path.addLine(to: CGPoint(x: right, y: 1024))
    path.addArc(tangent1End: CGPoint(x: right, y: bottom),
                tangent2End: CGPoint(x: left, y: bottom), radius: markCornerRadius)
    path.addArc(tangent1End: CGPoint(x: left, y: bottom),
                tangent2End: CGPoint(x: left, y: 1024), radius: markCornerRadius)
    path.closeSubpath()
    return path
}

/// The wordmark, drawn only where it can be read. Below 256px "brim" is four grey smudges,
/// so the small sizes carry the mark alone.
func drawWordmark() {
    let font = NSFont(name: "HelveticaNeue-Bold", size: 118)
        ?? NSFont.systemFont(ofSize: 118, weight: .bold)
    let text = NSAttributedString(string: "brim", attributes: [
        .font: font,
        .kern: -1.2,
        .foregroundColor: NSColor(srgbRed: 0.49, green: 0.506, blue: 0.537, alpha: 1)
    ])
    // The design file puts the baseline at y=860 in a y-down space. `draw(at:)` takes the
    // bottom-left of the glyph box, which sits a descender below the baseline.
    let baseline: CGFloat = 1024 - 860
    text.draw(at: CGPoint(x: (1024 - text.size().width) / 2, y: baseline + font.descender))
}

let folder = URL(fileURLWithPath: "dist/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        // Use explicit pixel dimensions so exports are independent of display scale.
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))

        // The artwork is a full-bleed 1024 square; macOS icons are inset so they sit at the
        // same visual size as every other icon in the Dock.
        let inset: CGFloat = 50
        let unit = CGFloat(pixels) / 1024
        context.scaleBy(x: unit, y: unit)
        context.translateBy(x: inset, y: inset)
        context.scaleBy(x: (1024 - inset * 2) / 1024, y: (1024 - inset * 2) / 1024)

        context.saveGState()
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                               cornerWidth: tileCornerRadius, cornerHeight: tileCornerRadius,
                               transform: nil))
        context.clip()

        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

        context.setFillColor(NSColor.white.cgColor)
        context.addPath(notchPath())
        context.fillPath()

        if pixels >= 256 { drawWordmark() }
        context.restoreGState()

        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
