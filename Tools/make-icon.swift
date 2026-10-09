#!/usr/bin/env swift
//
// Draws Resources/AppIcon.icns. Run it from the project root when the icon
// needs changing; the build itself just copies the finished .icns.
//
//   swift Tools/make-icon.swift
//
// The mark is an X, drawn in the colors the mic's rings cycle through, on the
// usual macOS rounded square.

import AppKit

let canvas: CGFloat = 1024          // everything below is laid out on this grid
let inset: CGFloat = 100            // macOS leaves the art short of the edges
let corner: CGFloat = 185
let stroke: CGFloat = 128
let arm: CGFloat = 250              // distance from center to each arm's tip

let ringColors: [CGColor] = [
    NSColor(srgbRed: 1.00, green: 0.17, blue: 0.23, alpha: 1).cgColor,
    NSColor(srgbRed: 1.00, green: 0.62, blue: 0.09, alpha: 1).cgColor,
    NSColor(srgbRed: 0.25, green: 0.86, blue: 0.40, alpha: 1).cgColor,
    NSColor(srgbRed: 0.20, green: 0.78, blue: 0.95, alpha: 1).cgColor,
    NSColor(srgbRed: 0.45, green: 0.40, blue: 0.98, alpha: 1).cgColor,
    NSColor(srgbRed: 0.94, green: 0.33, blue: 0.86, alpha: 1).cgColor,
]

func gradient(_ colors: [CGColor]) -> CGGradient {
    let locations = (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
    return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: colors as CFArray,
                      locations: locations)!
}

/// The two crossing arms, as one path.
func xPath() -> CGPath {
    let center = canvas / 2
    let path = CGMutablePath()
    for dx in [-1.0, 1.0] as [CGFloat] {
        path.move(to: CGPoint(x: center - arm * dx, y: center - arm))
        path.addLine(to: CGPoint(x: center + arm * dx, y: center + arm))
    }
    return path.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func draw(into context: CGContext, size: CGFloat) {
    context.scaleBy(x: size / canvas, y: size / canvas)

    // Rounded square, dark so the colors stay bright on it.
    let plate = CGPath(roundedRect: CGRect(x: inset, y: inset,
                                           width: canvas - inset * 2,
                                           height: canvas - inset * 2),
                       cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.saveGState()
    context.addPath(plate)
    context.clip()
    context.drawLinearGradient(
        gradient([NSColor(srgbRed: 0.09, green: 0.09, blue: 0.12, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.20, green: 0.20, blue: 0.25, alpha: 1).cgColor]),
        start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: canvas - inset), options: [])
    context.restoreGState()

    let mark = xPath()

    // A soft glow, the same thing the rings do in the window's preview.
    context.saveGState()
    context.addPath(plate)
    context.clip()
    context.setShadow(offset: .zero, blur: 90,
                      color: NSColor(srgbRed: 0.6, green: 0.4, blue: 1, alpha: 0.75).cgColor)
    context.addPath(mark)
    context.setFillColor(NSColor(srgbRed: 0.5, green: 0.3, blue: 0.9, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    // The mark itself, running through the ring colors corner to corner.
    context.saveGState()
    context.addPath(plate)
    context.clip()
    context.addPath(mark)
    context.clip()
    let center = canvas / 2
    context.drawLinearGradient(gradient(ringColors),
                               start: CGPoint(x: center - arm, y: center + arm),
                               end: CGPoint(x: center + arm, y: center - arm),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    // A highlight along the top edge, so the plate reads as a surface.
    context.saveGState()
    context.addPath(plate)
    context.clip()
    context.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
    context.setLineWidth(6)
    context.addPath(plate)
    context.strokePath()
    context.restoreGState()
}

func render(size: CGFloat) -> Data {
    let pixels = Int(size)
    let context = CGContext(data: nil, width: pixels, height: pixels,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    draw(into: context, size: size)
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: pixels, height: pixels)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Write the iconset and fold it into an .icns

let root = FileManager.default.currentDirectoryPath
let iconset = URL(fileURLWithPath: root).appendingPathComponent("build/AppIcon.iconset")
let resources = URL(fileURLWithPath: root).appendingPathComponent("Resources")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: CGFloat(base * scale)).write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path,
                      "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

// A big PNG is handy for looking at the result.
try render(size: 1024).write(to: iconset.appendingPathComponent("preview-1024.png"))
print("wrote Resources/AppIcon.icns")
