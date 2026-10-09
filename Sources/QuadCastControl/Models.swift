import AppKit
import SwiftUI

/// A color stored as 0...1 sRGB components (Codable, so it can be persisted).
struct RGB: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        r = Double(ns.redComponent)
        g = Double(ns.greenComponent)
        b = Double(ns.blueComponent)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    func scaled(_ k: Double) -> RGB {
        let k = max(0, min(1, k))
        return RGB(r: r * k, g: g * k, b: b * k)
    }

    static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let t = max(0, min(1, t))
        return RGB(r: a.r + (b.r - a.r) * t,
                   g: a.g + (b.g - a.g) * t,
                   b: a.b + (b.b - a.b) * t)
    }

    /// The three bytes the mic expects.
    var bytes: (UInt8, UInt8, UInt8) {
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return (byte(r), byte(g), byte(b))
    }

    static let black = RGB(r: 0, g: 0, b: 0)
    static let red = RGB(hex: 0xF20000)
    static let rainbow: [RGB] = [
        RGB(hex: 0xFF0000), RGB(hex: 0xFFAA00), RGB(hex: 0x00FF00),
        RGB(hex: 0x00FFFF), RGB(hex: 0x0000FF), RGB(hex: 0xFF00FF),
    ]
}

enum LightMode: String, Codable, CaseIterable, Identifiable {
    case solid, blink, cycle, wave, lightning, pulse, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .blink: return "Blink"
        case .cycle: return "Cycle"
        case .wave: return "Wave"
        case .lightning: return "Lightning"
        case .pulse: return "Pulse"
        case .off: return "Off"
        }
    }

    var isAnimated: Bool { self != .solid && self != .off }
    var allowsMultipleColors: Bool { isAnimated }
    /// Modes that look wrong with a single color get a rainbow by default.
    var wantsPalette: Bool { self == .cycle || self == .wave }
}

struct ZoneConfig: Codable, Equatable {
    var mode: LightMode = .solid
    var colors: [RGB] = [.red]
    var brightness: Double = 100   // 0...100
    var speed: Double = 50         // 0...100
}

struct LightingConfig: Codable, Equatable {
    var linked = true
    var upper = ZoneConfig()
    var lower = ZoneConfig()

    /// When linked, the lower ring mirrors the upper ring's settings.
    var effectiveLower: ZoneConfig { linked ? upper : lower }

    static let allOff = LightingConfig(
        linked: true,
        upper: ZoneConfig(mode: .off, colors: [.black]),
        lower: ZoneConfig(mode: .off, colors: [.black])
    )
}

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var lighting: LightingConfig
}

/// Everything saved between launches.
struct SavedState: Codable {
    var lighting = LightingConfig()
    var presets: [Preset] = []

    private static let key = "QuadCastControl.state.v1"

    static func load() -> SavedState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return SavedState() }
        return state
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
