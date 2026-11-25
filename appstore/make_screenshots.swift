// Builds the App Store screenshot set from raw simulator captures.
//
// Why a script rather than a design tool: the captures have to be retaken
// every time the UI moves, and a set that is expensive to rebuild is a set
// that silently goes stale. Run it again after any visual change.
//
//   swift appstore/make_screenshots.swift <raw-dir> <out-dir>
//
// Raw captures come from an iPhone 17 Pro Max simulator, which is 1320x2868 -
// exactly the 6.9" size App Store Connect requires. Anything else and Apple
// refuses the upload, so the canvas is the same size and the device art is
// composed inside it rather than scaled afterwards.

import AppKit
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_screenshots.swift <raw-dir> <out-dir>\n".data(using: .utf8)!)
    exit(2)
}
let rawDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// ---- the app's own typeface, so the captions and the UI agree ----
let fontDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("assets/google_fonts")
for name in ["Inter-Bold.ttf", "Inter-Regular.ttf", "Inter-Medium.ttf"] {
    let url = fontDir.appendingPathComponent(name)
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
func inter(_ size: CGFloat, bold: Bool) -> NSFont {
    NSFont(name: bold ? "Inter-Bold" : "Inter-Regular", size: size)
        ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
}

// ---- palette, taken from the app's own light theme ----
func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}
let ink = rgb(26, 26, 36)
let inkSoft = rgb(104, 104, 125)

struct Shot {
    let file: String          // raw capture, without extension
    let headline: String
    let sub: String
    let top: NSColor          // background gradient, top
    let bottom: NSColor       // background gradient, bottom
}

// Two tints alternating, so the set reads as one family on the product page
// rather than five unrelated images. Deliberately pale: the screenshot is the
// subject, and a loud background competes with it.
let cream = (rgb(248, 246, 243), rgb(238, 235, 248))
let lilac = (rgb(240, 238, 252), rgb(228, 226, 248))

let shots: [Shot] = [
    Shot(file: "raw-coach",
         headline: "Someone to\nthink with",
         sub: "Talk it through with Mynd, any time of day.",
         top: cream.0, bottom: cream.1),
    Shot(file: "raw-focus",
         headline: "Focus that\nactually holds",
         sub: "A timer, your music, and nothing else asking for you.",
         top: lilac.0, bottom: lilac.1),
    Shot(file: "raw-schedule",
         headline: "Your day,\naround real life",
         sub: "Plans that fit the calendar you already keep.",
         top: cream.0, bottom: cream.1),
    Shot(file: "raw-feed",
         headline: "A feed worth\nyour attention",
         sub: "Reading picked for focus, refreshed through the day.",
         top: lilac.0, bottom: lilac.1),
    Shot(file: "raw-paywall",
         headline: "Everything,\nunlocked",
         sub: "One subscription. Cancel any time in Settings.",
         top: cream.0, bottom: cream.1),
]

let W: CGFloat = 1320
let H: CGFloat = 2868

func draw(_ shot: Shot, index: Int) throws {
    let srcURL = rawDir.appendingPathComponent(shot.file + ".png")
    guard let src = NSImage(contentsOf: srcURL) else {
        FileHandle.standardError.write("missing \(srcURL.path)\n".data(using: .utf8)!)
        return
    }

    // An explicit bitmap rep, not NSImage.lockFocus. lockFocus adopts the
    // backing scale of the display it runs on, so on a Retina Mac it silently
    // produces a 2640x5736 file. App Store Connect wants exactly 1320x2868
    // and refuses anything else, so the pixel count is pinned here rather
    // than left to whichever machine runs this.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(W), pixelsHigh: Int(H),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }
    rep.size = NSSize(width: W, height: H)

    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    // ---- background ----
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space,
                          colors: [shot.top.cgColor, shot.bottom.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // ---- caption ----
    // Measured and drawn from the top down. Laying it out from the bottom
    // would move every caption whenever one of them wrapped to a third line.
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineSpacing = -6

    let headline = NSAttributedString(string: shot.headline, attributes: [
        .font: inter(112, bold: true),
        .foregroundColor: ink,
        .paragraphStyle: para,
        .kern: -2.5,
    ])
    let subPara = NSMutableParagraphStyle()
    subPara.alignment = .center
    subPara.lineSpacing = 8
    let sub = NSAttributedString(string: shot.sub, attributes: [
        .font: inter(46, bold: false),
        .foregroundColor: inkSoft,
        .paragraphStyle: subPara,
    ])

    let side: CGFloat = 96
    let textWidth = W - side * 2
    let hRect = headline.boundingRect(with: NSSize(width: textWidth, height: 600),
                                      options: [.usesLineFragmentOrigin])
    let sRect = sub.boundingRect(with: NSSize(width: textWidth, height: 300),
                                 options: [.usesLineFragmentOrigin])

    let topMargin: CGFloat = 150
    headline.draw(with: NSRect(x: side, y: H - topMargin - hRect.height,
                               width: textWidth, height: hRect.height),
                  options: [.usesLineFragmentOrigin])
    let subY = H - topMargin - hRect.height - 34 - sRect.height
    sub.draw(with: NSRect(x: side, y: subY, width: textWidth, height: sRect.height),
             options: [.usesLineFragmentOrigin])

    // ---- the device ----
    // Bleeds off the bottom edge rather than floating with a margin under it.
    // A fully contained phone reads as a sticker on a slide; a cropped one
    // reads as a window into the app, which is what this is.
    let deviceW = W * 0.76
    let scale = deviceW / W
    let deviceH = H * scale
    let deviceX = (W - deviceW) / 2
    let deviceY = subY - 110 - deviceH   // may fall below 0: that is the crop

    let frame = CGRect(x: deviceX, y: deviceY, width: deviceW, height: deviceH)
    let radius: CGFloat = 62

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 70,
                  color: NSColor(srgbRed: 0.18, green: 0.16, blue: 0.32, alpha: 0.22).cgColor)
    let shadowPath = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    NSColor.white.setFill()
    shadowPath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    let clip = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    clip.addClip()
    src.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()

    // A hairline edge, so a white app screen does not dissolve into a pale
    // background with no boundary at all.
    ctx.saveGState()
    NSColor(srgbRed: 0.22, green: 0.20, blue: 0.36, alpha: 0.14).setStroke()
    let edge = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    edge.lineWidth = 2
    edge.stroke()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    let name = String(format: "%02d-%@.png", index + 1,
                      shot.file.replacingOccurrences(of: "raw-", with: ""))
    try png.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name)  \(Int(W))x\(Int(H))")
}

for (i, shot) in shots.enumerated() {
    try draw(shot, index: i)
}
print("done: \(shots.count) screenshots in \(outDir.path)")
