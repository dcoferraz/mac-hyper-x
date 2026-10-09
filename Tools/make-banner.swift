#!/usr/bin/env swift
//
// Draws docs/banner.png, the image at the top of the README. Run it from the
// project root after the icon changes:
//
//   swift Tools/make-banner.swift
//
// It reads the icon that Tools/make-icon.swift already produced, so the two
// always agree.

import AppKit
import SwiftUI

let root = FileManager.default.currentDirectoryPath
let iconPath = root + "/Resources/AppIcon.icns"
let outPath = root + "/docs/banner.png"

guard let icon = NSImage(contentsOfFile: iconPath) else {
    FileHandle.standardError.write("cannot read \(iconPath)\n".data(using: .utf8)!)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

/// The same colors the app and the demo video use.
let ringGradient = LinearGradient(
    colors: [Color(red: 1.00, green: 0.17, blue: 0.23),
             Color(red: 1.00, green: 0.62, blue: 0.09),
             Color(red: 0.25, green: 0.86, blue: 0.40),
             Color(red: 0.20, green: 0.78, blue: 0.95),
             Color(red: 0.45, green: 0.40, blue: 0.98),
             Color(red: 0.94, green: 0.33, blue: 0.86)],
    startPoint: .leading, endPoint: .trailing)

struct Banner: View {
    let icon: NSImage

    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.067)

            // Soft washes, matching the video's backdrop.
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.45, green: 0.40, blue: 0.98).opacity(0.22), .clear],
                                     center: .center, startRadius: 0, endRadius: 420))
                .frame(width: 840, height: 840)
                .offset(x: -430, y: -210)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.20, green: 0.78, blue: 0.95).opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: 380))
                .frame(width: 760, height: 760)
                .offset(x: 470, y: 230)

            HStack(spacing: 38) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 152, height: 152)
                    .shadow(color: .black.opacity(0.55), radius: 26, y: 10)

                VStack(alignment: .leading, spacing: 14) {
                    Text("QuadCast Control")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(.white)
                        .kerning(-1.6)
                    Text("Native macOS control for the HyperX QuadCast S")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                    Capsule()
                        .fill(ringGradient)
                        .frame(width: 260, height: 5)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 60)
        }
        .frame(width: 1120, height: 300)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
func render() {
    let renderer = ImageRenderer(content: Banner(icon: icon))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
        exit(1)
    }
    try? FileManager.default.createDirectory(atPath: root + "/docs", withIntermediateDirectories: true)
    try? png.write(to: URL(fileURLWithPath: outPath))
    print("wrote docs/banner.png")
}

MainActor.assumeIsolated { render() }
