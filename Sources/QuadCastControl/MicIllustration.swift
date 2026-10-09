import SwiftUI

/// The mic, drawn the way it actually looks: a grille in a shock mount on a
/// stand, with the light showing through the grille's upper and lower halves.
///
/// Everything is one Canvas. Rebuilding real views 30 times a second runs a
/// full AppKit layout pass over whatever contains this, which costs far more
/// than the drawing does.
struct MicIllustration: View {
    let lighting: LightingConfig
    /// Nil while the mic hasn't reported a mute state yet.
    var muted: Bool?
    var height: CGFloat = 132

    @Environment(\.controlActiveState) private var activeState

    /// The drawing is laid out on this grid and scaled to fit.
    private static let grid = CGSize(width: 100, height: 158)

    private var scale: CGFloat { height / Self.grid.height }
    private var width: CGFloat { Self.grid.width * scale }

    private var paused: Bool {
        let moving = lighting.upper.mode.isAnimated || lighting.effectiveLower.mode.isAnimated
        return !moving || activeState == .inactive
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let upper = Effects.color(for: lighting.upper, ring: .upper, time: t)
            let lower = Effects.color(for: lighting.effectiveLower, ring: .lower, time: t)
            Canvas { canvas, _ in
                canvas.scaleBy(x: scale, y: scale)
                draw(upper: upper, lower: lower, on: canvas)
            }
            .frame(width: width, height: height)
        }
        .accessibilityLabel(muted == true ? "Mic preview, muted" : "Mic preview")
    }

    // MARK: - Drawing, on the 100 x 158 grid

    private func draw(upper: RGB, lower: RGB, on canvas: GraphicsContext) {
        let dim = muted == true ? 0.22 : 1.0
        let bodyRect = CGRect(x: 29, y: 4, width: 42, height: 100)

        drawStand(on: canvas)
        drawMount(on: canvas)

        // The grille, lit from behind in two halves.
        let body = Path(roundedRect: bodyRect, cornerRadius: 14)
        canvas.drawLayer { shell in
            shell.addFilter(.shadow(color: .black.opacity(0.5), radius: 5, y: 3))
            shell.fill(body, with: .color(Color(white: 0.13)))
        }

        let grille = bodyRect.insetBy(dx: 4, dy: 4)
        let halfHeight = grille.height / 2
        let upperHalf = CGRect(x: grille.minX, y: grille.minY, width: grille.width, height: halfHeight)
        let lowerHalf = CGRect(x: grille.minX, y: grille.midY, width: grille.width, height: halfHeight)

        canvas.drawLayer { lit in
            lit.clip(to: Path(roundedRect: grille, cornerRadius: 11))
            lit.fill(Path(upperHalf), with: .color(upper.color.opacity(dim)))
            lit.fill(Path(lowerHalf), with: .color(lower.color.opacity(dim)))
            // A dark seam where the two zones meet, as on the real grille.
            lit.fill(Path(CGRect(x: grille.minX, y: grille.midY - 0.6, width: grille.width, height: 1.2)),
                     with: .color(.black.opacity(0.6)))
            mesh(over: grille, on: lit)
        }

        // Glow spilling out of the grille.
        if muted != true {
            canvas.drawLayer { glow in
                glow.addFilter(.blur(radius: 6))
                glow.blendMode = .plusLighter
                glow.opacity = 0.45
                glow.fill(Path(upperHalf.insetBy(dx: -2, dy: -2)), with: .color(upper.color))
                glow.fill(Path(lowerHalf.insetBy(dx: -2, dy: -2)), with: .color(lower.color))
            }
        }

        canvas.stroke(Path(roundedRect: grille, cornerRadius: 11),
                      with: .color(.black.opacity(0.55)), lineWidth: 1.5)
        canvas.stroke(body, with: .color(.white.opacity(0.16)), lineWidth: 1)

        if muted == true { drawMuteBadge(on: canvas) }
    }

    /// Fine horizontal lines, which is what reads as a mesh at this size.
    private func mesh(over rect: CGRect, on canvas: GraphicsContext) {
        var lines = Path()
        var y = rect.minY + 1.5
        while y < rect.maxY {
            lines.move(to: CGPoint(x: rect.minX, y: y))
            lines.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += 3
        }
        canvas.stroke(lines, with: .color(.black.opacity(0.28)), lineWidth: 1)
    }

    /// The shock mount: a U-shaped cradle the body sits in.
    private func drawMount(on canvas: GraphicsContext) {
        var cradle = Path()
        cradle.move(to: CGPoint(x: 23, y: 14))
        cradle.addLine(to: CGPoint(x: 23, y: 99))
        cradle.addQuadCurve(to: CGPoint(x: 77, y: 99), control: CGPoint(x: 50, y: 126))
        cradle.addLine(to: CGPoint(x: 77, y: 14))
        canvas.stroke(cradle, with: .color(Color(white: 0.27)),
                      style: StrokeStyle(lineWidth: 7, lineCap: .round))
        canvas.stroke(cradle, with: .color(.white.opacity(0.1)),
                      style: StrokeStyle(lineWidth: 1))
    }

    private func drawStand(on canvas: GraphicsContext) {
        let metal = Color(white: 0.3)
        let post = Path(roundedRect: CGRect(x: 46, y: 106, width: 8, height: 30), cornerRadius: 3)
        canvas.fill(post, with: .color(metal))
        let base = Path(ellipseIn: CGRect(x: 28, y: 132, width: 44, height: 15))
        canvas.drawLayer { plinth in
            plinth.addFilter(.shadow(color: .black.opacity(0.45), radius: 4, y: 2))
            plinth.fill(base, with: .color(Color(white: 0.22)))
        }
        canvas.stroke(base, with: .color(.white.opacity(0.14)), lineWidth: 1)
    }

    private func drawMuteBadge(on canvas: GraphicsContext) {
        let center = CGPoint(x: 50, y: 54)
        let radius: CGFloat = 17
        let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2))
        canvas.fill(circle, with: .color(.black.opacity(0.6)))
        canvas.stroke(circle, with: .color(.white.opacity(0.85)), lineWidth: 2.5)
        var slash = Path()
        slash.move(to: CGPoint(x: center.x - 9, y: center.y - 9))
        slash.addLine(to: CGPoint(x: center.x + 9, y: center.y + 9))
        canvas.stroke(slash, with: .color(.white.opacity(0.85)),
                      style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
}
