// Draws the marketing shot of the notch: the top of a Mac display, with the real menu
// bar across it and the notch hanging on its left edge.
//
//   MENUBAR=menubar.png swift Scripts/notch-mockup.swift <notch-capture.png> <out.png>
//
// Only the top band of the display is in frame. The top, left and right edges are
// visible and the bottom runs off the picture, which is what makes it read as part of a
// screen rather than a floating slab. Capture the menu bar full width, at the display's
// own scale:
//
//   screencapture -x -R0,0,<screen points wide>,25 -t png menubar.png
//
// The notch itself is a real capture rather than a redrawing, so the rings, the
// percentages and the shape are whatever the app actually put on screen. Capture it on
// its own, with transparency and no drop shadow, then click the notch:
//
//   screencapture -w -o -t png notch.png
//
// The hover card is captured the same way, while hovering a ring, and rendered with
// --card. Numbers in both are read from real accounts. Never stage them: a picture of
// invented usage is the same lie as an invented reading.
//
// Everything around it is generated here, so no part of anyone's desktop, and no
// Apple artwork, ends up in the picture.
import AppKit

let args = CommandLine.arguments
// --card renders the hover card on the same neutral ground instead of a display corner,
// so the two pictures sit together without looking like they came from two places.
let cardMode = args.contains("--card")
let positional = args.dropFirst().filter { !$0.hasPrefix("--") }
guard positional.count == 2 else {
    FileHandle.standardError.write("usage: notch-mockup.swift [--card] <capture.png> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let inputPath = positional[positional.startIndex]
let outputPath = positional[positional.index(after: positional.startIndex)]
// The menu bar is a real capture too. Drawing a facsimile would mean inventing a
// clock, a battery level and a set of status items, and the point of this picture is
// that it is the app in its actual surroundings.
let menuBarPath = ProcessInfo.processInfo.environment["MENUBAR"]
let menuBar = menuBarPath.flatMap { NSImage(contentsOfFile: $0) }
guard let notch = NSImage(contentsOfFile: inputPath) else {
    FileHandle.standardError.write("cannot read \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

let page = NSColor(calibratedWhite: 0.94, alpha: 1)

// The card needs no display around it: it is a panel the app floats over whatever is
// behind it, so a plain ground and a shadow is the honest presentation.
if cardMode {
    let margin: CGFloat = 34
    let width = notch.size.width * 2, height = notch.size.height * 2
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(width + margin * 2), pixelsHigh: Int(height + margin * 2),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setFillColor(page.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width + margin * 2, height: height + margin * 2))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 26,
                  color: NSColor(calibratedWhite: 0, alpha: 0.34).cgColor)
    notch.draw(in: CGRect(x: margin, y: margin, width: width, height: height),
               from: CGRect(origin: .zero, size: notch.size), operation: .sourceOver, fraction: 1)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath) at \(rep.pixelsWide)x\(rep.pixelsHigh)")
    exit(0)
}

let scale: CGFloat = 2
let canvas = CGSize(width: 1440 * scale, height: 330 * scale)
let bezel: CGFloat = 11 * scale     // the sliver of hardware around the picture
let inset: CGFloat = 18 * scale     // how far the display sits inside the frame
let corner: CGFloat = 26 * scale
let bleed: CGFloat = 240 * scale    // how far the display runs off the bottom

// Drawing into a bitmap of a stated size, rather than lockFocus on an NSImage, keeps
// the output at exactly the pixel dimensions asked for on any display.
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx
let ctx = nsCtx.cgContext

// The page behind the display. Light and neutral, so the shot drops onto a README or a
// portfolio page without dragging a colour scheme along with it.
ctx.setFillColor(page.cgColor)
ctx.fill(CGRect(origin: .zero, size: canvas))

// The display, positioned so only its top left corner is in frame.
let screen = CGRect(x: inset + bezel,
                    y: -bleed,
                    width: canvas.width - (inset + bezel) * 2,
                    height: canvas.height - inset - bezel + bleed)
let outer = screen.insetBy(dx: -bezel, dy: -bezel)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 5 * scale, height: -5 * scale), blur: 22 * scale,
              color: NSColor(calibratedWhite: 0, alpha: 0.30).cgColor)
ctx.addPath(CGPath(roundedRect: outer, cornerWidth: corner + bezel * 0.7,
                   cornerHeight: corner + bezel * 0.7, transform: nil))
ctx.setFillColor(NSColor(calibratedWhite: 0.10, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

// The wallpaper. Generated, so nothing of Apple's ships in this file.
let screenPath = CGPath(roundedRect: screen, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.saveGState()
ctx.addPath(screenPath)
ctx.clip()
// The desktop. The menu bar is translucent, so it carries the colour of whatever was
// behind it when it was captured. A wallpaper invented independently of that leaves a
// visible seam along the bottom of the bar, so the top of this one is sampled from the
// bar itself and then falls away into shadow.
func sample(_ image: NSImage?, atFraction x: CGFloat) -> NSColor? {
    guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    let px = min(rep.pixelsWide - 1, max(0, Int(CGFloat(rep.pixelsWide) * x)))
    return rep.colorAt(x: px, y: rep.pixelsHigh - 1)?.usingColorSpace(.deviceRGB)
}

let sampled = [0.04, 0.5, 0.96].compactMap { sample(menuBar, atFraction: $0) }
if sampled.count == 3 {
    // Across, in the bar's own colours, so the seam disappears.
    if let across = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: sampled.map { $0.cgColor } as CFArray, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(across, start: CGPoint(x: screen.minX, y: 0),
                               end: CGPoint(x: screen.maxX, y: 0), options: [])
    }
    // And down into shadow, which is what a wallpaper does below its sky.
    if let down = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [NSColor(calibratedWhite: 0, alpha: 0).cgColor,
                                      NSColor(calibratedWhite: 0.04, alpha: 0.84).cgColor] as CFArray,
                             locations: [0, 1]) {
        ctx.drawLinearGradient(down, start: CGPoint(x: 0, y: screen.maxY),
                               end: CGPoint(x: 0, y: screen.maxY - canvas.height * 1.2), options: [])
    }
} else {
    let colours = [
        NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.32, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.33, green: 0.24, blue: 0.37, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.64, green: 0.41, blue: 0.35, alpha: 1).cgColor
    ]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colours as CFArray, locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: screen.minX, y: screen.maxY),
                               end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
    }
}

// The menu bar, as captured. It is drawn at the width it was taken at, so the clock,
// the status items and the menu titles keep their real proportions.
if let menuBar {
    let height = screen.width * (menuBar.size.height / menuBar.size.width)
    menuBar.draw(in: CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height),
                 from: CGRect(origin: .zero, size: menuBar.size), operation: .sourceOver, fraction: 1)
} else {
    // Without a capture, a plain translucent strip. Never a drawn imitation of one.
    ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
    ctx.fill(CGRect(x: screen.minX, y: screen.maxY - 25 * scale, width: screen.width, height: 25 * scale))
}
ctx.restoreGState()

// The notch, flush against the display's left edge. Its own shape curves out into that
// edge, so any gap here would look like a mistake.
//
// Sized as a share of the frame rather than at the capture's own size. A retina capture
// reports its size in points, which would draw it at half the pixels it contains and
// leave it a detail in the corner of a picture that exists to show it.
let aspect = notch.size.width / notch.size.height
let notchHeight = canvas.height * 0.80
let target = CGRect(x: screen.minX,
                    y: screen.maxY - 25 * scale - notchHeight,
                    width: notchHeight * aspect,
                    height: notchHeight)
ctx.saveGState()
ctx.addPath(screenPath)
ctx.clip()
notch.draw(in: target, from: CGRect(origin: .zero, size: notch.size),
           operation: .sourceOver, fraction: 1)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) at \(rep.pixelsWide)x\(rep.pixelsHigh)")
