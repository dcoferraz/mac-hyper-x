import AppKit
import SwiftUI

/// A color swatch that opens its own picker in a popover.
///
/// SwiftUI's ColorPicker hands off to the shared NSColorPanel, a free-floating
/// window that reopens wherever it was last used — often on another display.
/// This keeps the whole interaction attached to the swatch.
struct ColorWell: View {
    @Binding var color: Color
    @State private var showingPicker = false

    var body: some View {
        Button { showingPicker = true } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 30, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.3)))
                .shadow(color: color.opacity(0.5), radius: 3)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            ColorPalette(color: $color)
        }
        .accessibilityLabel("Color")
    }
}

/// Hue, saturation and brightness bars, plus one-click swatches.
struct ColorPalette: View {
    @Binding var color: Color

    @State private var hue = 0.0
    @State private var saturation = 1.0
    @State private var brightness = 1.0
    @State private var loaded = false

    private static let swatches: [RGB] = RGB.rainbow + [
        RGB(hex: 0xFFFFFF), RGB(hex: 0xFF8080), RGB(hex: 0x80FF80), RGB(hex: 0x8080FF),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(width: 44, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.3)))
                Text(hexLabel)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            bar("Hue", colors: hueStops, value: hue) { hue = $0; push() }
            bar("Saturation",
                colors: [Color(hue: hue, saturation: 0, brightness: brightness),
                         Color(hue: hue, saturation: 1, brightness: brightness)],
                value: saturation) { saturation = $0; push() }
            bar("Brightness",
                colors: [.black, Color(hue: hue, saturation: saturation, brightness: 1)],
                value: brightness) { brightness = $0; push() }

            Divider()

            HStack(spacing: 6) {
                ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                    Button {
                        color = swatch.color
                        load(force: true)
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { load() }
    }

    private var hueStops: [Color] {
        stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
            Color(hue: $0, saturation: 1, brightness: 1)
        }
    }

    private var hexLabel: String {
        let (r, g, b) = RGB(color).bytes
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func bar(_ title: String, colors: [Color], value: Double,
                     set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            GradientBar(colors: colors, value: value, set: set)
        }
    }

    /// Hue and saturation can't be recovered from a black or grey color, so the
    /// bars keep their own state and only read the binding when they open.
    private func load(force: Bool = false) {
        guard !loaded || force else { return }
        loaded = true
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }

    private func push() {
        color = Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

/// A draggable gradient strip.
struct GradientBar: View {
    let colors: [Color]
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.2)))
                .overlay(alignment: .leading) {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .shadow(radius: 1)
                        .offset(x: max(0, min(width - 14, value * width - 7)))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    set(min(1, max(0, drag.location.x / width)))
                })
        }
        .frame(height: 18)
    }
}
