import AppKit

// The install window's backdrop. Drawn rather than stored as a binary, for the same
// reason the icon is: the numbers here have to agree with the icon positions the build
// script gives Finder, and two files that must agree should be one file.
//
// Light ground on purpose. Finder draws the icon labels itself, in the system's own
// label colour, and on a black backdrop "Brim" and "Applications" would disappear.
// The brand shows up as the notch instead, hanging from the top edge of the window,
// which is the one place on a Mac it actually lives.

let width: CGFloat = 640
let height: CGFloat = 400

/// Must match the positions the build script sets, or the arrow points at nothing.
let appCentre = CGPoint(x: 170, y: 175)
let applicationsCentre = CGPoint(x: 470, y: 175)
let iconSize: CGFloat = 100

/// Design coordinates run down the page, the way the layout is described. The context
/// runs up it.
func y(_ down: CGFloat) -> CGFloat { height - down }

func draw(into context: CGContext) {
    // A barely-there vertical gradient. Flat white reads as an unfinished window.
    let colours = [NSColor(srgbRed: 0.980, green: 0.980, blue: 0.976, alpha: 1).cgColor,
                   NSColor(srgbRed: 0.925, green: 0.922, blue: 0.914, alpha: 1).cgColor]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colours as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height),
                                   end: CGPoint(x: 0, y: 0), options: [])
    }

    // The mark, hanging from the top edge of the window like the app hangs from the top
    // edge of the screen. Same proportions as the icon: corners rounded at 72/205 of the
    // drop, square where it meets the edge.
    let notchWidth: CGFloat = 188
    let notchDrop: CGFloat = 30
    let radius = notchDrop * 72 / 205
    let left = (width - notchWidth) / 2
    let right = left + notchWidth
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: left, y: y(0)))
    notch.addLine(to: CGPoint(x: right, y: y(0)))
    notch.addArc(tangent1End: CGPoint(x: right, y: y(notchDrop)),
                 tangent2End: CGPoint(x: left, y: y(notchDrop)), radius: radius)
    notch.addArc(tangent1End: CGPoint(x: left, y: y(notchDrop)),
                 tangent2End: CGPoint(x: left, y: y(0)), radius: radius)
    notch.closeSubpath()
    context.setFillColor(NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1).cgColor)
    context.addPath(notch)
    context.fillPath()

    // The arrow, in the gap the two icons leave. It starts and ends clear of them
    // rather than at their centres, so it never runs under a label.
    let arrowY = y(appCentre.y)
    let start = appCentre.x + iconSize / 2 + 30
    let end = applicationsCentre.x - iconSize / 2 - 30
    let head: CGFloat = 15
    let ink = NSColor(srgbRed: 0.62, green: 0.61, blue: 0.60, alpha: 1).cgColor
    context.setStrokeColor(ink)
    context.setFillColor(ink)
    context.setLineWidth(3)
    context.setLineCap(.butt)
    context.move(to: CGPoint(x: start, y: arrowY))
    context.addLine(to: CGPoint(x: end - head + 1, y: arrowY))
    context.strokePath()
    // A solid head. An open chevron at this weight reads as a stray ">" sitting off the
    // end of the line rather than as one arrow.
    context.move(to: CGPoint(x: end, y: arrowY))
    context.addLine(to: CGPoint(x: end - head, y: arrowY + head * 0.62))
    context.addLine(to: CGPoint(x: end - head, y: arrowY - head * 0.62))
    context.closePath()
    context.fillPath()

    // One instruction. The window already shows an app and a folder; it does not also
    // need a paragraph.
    let caption = NSAttributedString(string: "Drag Brim into your Applications folder", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.42, green: 0.41, blue: 0.40, alpha: 1)
    ])
    caption.draw(at: CGPoint(x: (width - caption.size().width) / 2, y: y(300)))
}

// Both scales in one file, so Finder picks the right one on a Retina display and the
// backdrop is not a blurry upscale.
var pages: [NSBitmapImageRep] = []
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    // Both pages stay at 72 dpi, so each one's points equal its pixels. Giving the 2x
    // page a 1x size instead marks it 144 dpi, and `tiffutil -cathidpicheck` then fails
    // to pair them: Finder picks the larger page and draws it at 1:1, which puts a
    // double-size caption across the Applications folder.
    bitmap.size = NSSize(width: Int(width) * scale, height: Int(height) * scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw(into: context)
    NSGraphicsContext.restoreGraphicsState()
    pages.append(bitmap)
}

try FileManager.default.createDirectory(atPath: "dist", withIntermediateDirectories: true)
for (index, page) in pages.enumerated() {
    let name = index == 0 ? "dist/dmg-background.png" : "dist/dmg-background@2x.png"
    try page.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
}
