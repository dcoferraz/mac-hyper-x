import SwiftUI

/// The pickup pattern set by the dial on the back of the mic.
///
/// Read-only: the dial is hardware, and nothing in the protocol sets it. The
/// mic reports the position in the same status report the mute sensor uses.
///
/// The raw values run the opposite way to the icons printed on the dial, which
/// read Stereo, Omnidirectional, Cardioid, Bidirectional from left to right.
/// These values were read off the hardware.
enum PolarPattern: UInt8, CaseIterable, Identifiable {
    case bidirectional = 0
    case cardioid = 1
    case omnidirectional = 2
    case stereo = 3

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .bidirectional: return "Bidirectional"
        case .cardioid: return "Cardioid"
        case .omnidirectional: return "Omnidirectional"
        case .stereo: return "Stereo"
        }
    }

    /// What the pattern is good for, in one short phrase.
    var detail: String {
        switch self {
        case .bidirectional: return "Front and back"
        case .cardioid: return "Front only"
        case .omnidirectional: return "All directions"
        case .stereo: return "Left and right"
        }
    }
}

/// The pattern drawn as its pickup shape, the same way the dial marks it.
struct PolarPatternIcon: View {
    let pattern: PolarPattern
    var size: CGFloat = 18

    var body: some View {
        Canvas { canvas, _ in
            let box = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
            canvas.stroke(shape(in: box),
                          with: .color(.primary.opacity(0.85)),
                          lineWidth: max(1, size * 0.09))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func shape(in box: CGRect) -> Path {
        switch pattern {
        case .omnidirectional:
            return Path(ellipseIn: box)

        case .stereo:
            // Two overlapping lobes, as on the dial.
            let width = box.width * 0.62
            var path = Path()
            path.addEllipse(in: CGRect(x: box.minX, y: box.midY - width / 2,
                                       width: width, height: width))
            path.addEllipse(in: CGRect(x: box.maxX - width, y: box.midY - width / 2,
                                       width: width, height: width))
            return path

        case .cardioid:
            // r = (1 + cos t) / 2, turned so the lobe points up.
            return polar(in: box) { (1 + cos($0)) / 2 }

        case .bidirectional:
            // A figure of eight: one lobe forward, one back.
            return polar(in: box) { abs(cos($0)) }
        }
    }

    /// Traces a polar curve, scaled to fill the box.
    private func polar(in box: CGRect, radius: (Double) -> Double) -> Path {
        let steps = 96
        var points: [CGPoint] = []
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let r = radius(t)
            // Rotate a quarter turn so the main lobe points up the view.
            points.append(CGPoint(x: r * sin(t), y: -r * cos(t)))
        }
        let maxX = points.map { abs($0.x) }.max() ?? 1
        let maxY = points.map { abs($0.y) }.max() ?? 1
        let scale = min(box.width / (maxX * 2), box.height / (maxY * 2))

        var path = Path()
        for (index, point) in points.enumerated() {
            let placed = CGPoint(x: box.midX + point.x * scale,
                                 y: box.midY + point.y * scale)
            if index == 0 { path.move(to: placed) } else { path.addLine(to: placed) }
        }
        path.closeSubpath()
        return path
    }
}
