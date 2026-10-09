import Foundation

enum Zone { case upper, lower }

/// Pure functions: given a zone's settings and the elapsed time, what color
/// should that ring be right now? The same code drives the real mic and the
/// on-screen preview, so they always match.
enum Effects {
    static func color(for zone: ZoneConfig, ring: Zone, time t: Double) -> RGB {
        let colors = zone.colors.isEmpty ? [RGB.red] : zone.colors
        let s = max(0, min(100, zone.speed)) / 100   // 0 = slowest, 1 = fastest

        let raw: RGB
        switch zone.mode {
        case .off:
            raw = .black

        case .solid:
            raw = colors[0]

        case .blink:
            // Each color is on for half a segment, then off for half.
            let segment = lerp(1.6, 0.2, s)
            let pos = t / segment
            let index = Int(pos) % colors.count
            raw = pos.truncatingRemainder(dividingBy: 1) < 0.5 ? colors[index] : .black

        case .cycle, .wave:
            let palette = colors.count >= 2 ? colors : RGB.rainbow
            let segment = lerp(7.0, 0.66, s)
            var pos = t / segment
            // Wave: the lower ring runs one color ahead of the upper ring.
            if zone.mode == .wave && ring == .lower { pos += 1 }
            raw = gradient(palette, at: pos)

        case .lightning, .pulse:
            let gap = lerp(0.5, 0.05, s)
            let rise = lerp(0.55, 0.165, s)
            let fall = lerp(7.2, 1.15, s)
            let flash = rise + fall + gap
            let total = flash * Double(colors.count)

            var tt = t
            // Lightning: rings are offset. Pulse: rings are in sync.
            if zone.mode == .lightning && ring == .lower { tt -= gap + rise }
            let p = wrap(tt, total)
            let index = min(colors.count - 1, Int(p / flash))
            let f = p - Double(index) * flash
            let c = colors[index]

            if f < rise {
                raw = c.scaled(f / rise)
            } else if f < rise + fall {
                raw = c.scaled(1 - (f - rise) / fall)
            } else {
                raw = .black
            }
        }

        return raw.scaled(zone.brightness / 100)
    }

    private static func gradient(_ colors: [RGB], at pos: Double) -> RGB {
        let n = colors.count
        let base = Int(floor(pos))
        let i = ((base % n) + n) % n
        let frac = pos - floor(pos)
        return RGB.lerp(colors[i], colors[(i + 1) % n], frac)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func wrap(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
}
