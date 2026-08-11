import SwiftUI

/// A rebuilt venue backdrop, drawn as a layered scene rather than a scatter of props.
///
/// Authored in design's 860 x 400 reference frame - wall 0-300, wainscot 236-300, floor
/// 300-400, counter 340-400 - so every number below can be read straight off the art
/// direction. `x` and `y` map to fractions of the whole stage, which is why the two layers can
/// be inserted at different depths in `VenueStageView` and still line up: they share one
/// coordinate space, not one canvas.
///
/// Rooms move onto this path one at a time (see `rebuilt`); anything not listed still draws
/// through the original `VenuePropsView`, so a half-finished sweep never ships a blank room.
///
/// Motion is deliberately absent. Design specifies steam, garland sway and flicker, but the
/// venue stage is on screen for the entire session and is currently free per frame, so the
/// loops are held for a later pass and every element is drawn in design's own reduce-motion
/// rest pose.
struct VenueSceneView: View {
    enum Layer {
        /// Everything behind the floor plane: wall texture, wainscot, built-ins, hanging layer.
        case wall
        /// Floor material, drawn over the floor gradient.
        case floor
    }

    let theme: VenueTheme
    let palette: VenuePalette
    let layer: Layer

    /// Which rooms have been rebuilt. Everything else falls through to the legacy props.
    static let rebuilt: Set<VenueTheme> = [.burger]

    // Material colours. These are shared across every room on purpose - only *structural*
    // colour comes from `VenuePalette`, so the coin-priced neon skin stays a pure data change.
    private static let hardware = Color(hex: "#3A3346")
    private static let wood = Color(hex: "#5C4632")
    private static let cream = Color(hex: "#F2EDE2")
    private static let warmGlow = Color(hex: "#FFB84D")

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x / 860 * rect.width, y: rect.minY + y / 400 * rect.height)
            }
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: rect.minX + x / 860 * rect.width, y: rect.minY + y / 400 * rect.height,
                       width: w / 860 * rect.width, height: h / 400 * rect.height)
            }
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                Path(roundedRect: box(x, y, w, h), cornerRadius: radius / 860 * rect.width)
            }
            func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
                Path(ellipseIn: box(cx - rx, cy - ry, rx * 2, ry * 2))
            }
            /// Stroke widths key off the smaller axis, like `VenueProps` does, so a batten line
            /// does not fatten into a ribbon on a wide, short stage.
            let unit = min(rect.width / 860, rect.height / 400)
            func stroke(_ color: Color, _ width: CGFloat, opacity: Double = 1,
                        _ build: (inout Path) -> Void) {
                var path = Path(); build(&path)
                context.stroke(path, with: .color(color.opacity(opacity)),
                               style: StrokeStyle(lineWidth: max(0.5, width * unit), lineCap: .round))
            }
            func fill(_ path: Path, _ color: Color, outlined: Bool = true) {
                context.fill(path, with: .color(color))
                if outlined {
                    context.stroke(path, with: .color(Theme.outline), lineWidth: max(0.5, 3 * unit))
                }
            }
            /// The same fake bloom `VenueProps.glowDot` uses: three fills, no filter.
            func glowDot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color) {
                context.fill(ellipse(cx, cy, r * 2.6, r * 2.6), with: .color(color.opacity(0.14)))
                context.fill(ellipse(cx, cy, r * 1.7, r * 1.7), with: .color(color.opacity(0.26)))
                fill(ellipse(cx, cy, r, r), color)
            }

            switch (theme, layer) {
            case (.burger, .wall):
                // Panel seams, then the two horizontal courses.
                stroke(palette.wallBottom, 3, opacity: 0.5) { path in
                    for x in [120.0, 340.0, 520.0, 740.0] {
                        path.move(to: p(x, 0)); path.addLine(to: p(x, 236))
                    }
                }
                stroke(palette.wallBottom, 2, opacity: 0.35) { path in
                    for y in [88.0, 164.0] {
                        path.move(to: p(0, y)); path.addLine(to: p(860, y))
                    }
                }

                // Wainscot: the wall's own dark, lifted a touch rather than a new hex.
                context.fill(Path(box(0, 236, 860, 64)), with: .color(palette.wallBottom))
                context.fill(Path(box(0, 236, 860, 64)), with: .color(.white.opacity(0.06)))
                stroke(palette.wallBottom, 2.5, opacity: 0.6) { path in
                    for i in 0..<9 {
                        let x = 70 + Double(i) * 100
                        path.move(to: p(x, 236)); path.addLine(to: p(x, 300))
                    }
                }
                context.fill(Path(box(0, 232, 860, 4)), with: .color(palette.accent.opacity(0.3)))

                // Pass-through to the kitchen: the room's warm second light source.
                fill(rr(90, 66, 190, 124, 10), Self.hardware)
                context.fill(rr(102, 78, 166, 100, 5), with: .color(.black.opacity(0.55)))
                context.fill(rr(102, 78, 166, 100, 5), with: .radialGradient(
                    Gradient(colors: [Self.warmGlow.opacity(0.55), Self.warmGlow.opacity(0.05)]),
                    center: CGPoint(x: box(102, 78, 166, 100).midX, y: box(102, 78, 166, 100).midY),
                    startRadius: 0, endRadius: 100 / 860 * rect.width))
                stroke(.black, 3, opacity: 0.55) { path in
                    for y in [118.0, 148.0] {
                        path.move(to: p(112, y)); path.addLine(to: p(258, y))
                    }
                }
                context.fill(rr(120, 124, 30, 20, 3), with: .color(.black.opacity(0.5)))
                context.fill(rr(206, 124, 40, 20, 3), with: .color(.black.opacity(0.5)))
                // Pans hanging in the hatch, silhouetted against the glow.
                stroke(.black, 2.5, opacity: 0.75) { path in
                    path.move(to: p(130, 78)); path.addLine(to: p(130, 91))
                    path.move(to: p(164, 78)); path.addLine(to: p(164, 87))
                }
                context.fill(ellipse(130, 98, 7, 9), with: .color(.black.opacity(0.75)))
                context.fill(ellipse(164, 93, 6, 8), with: .color(.black.opacity(0.75)))
                // Sill with two plated orders waiting.
                context.fill(rr(90, 178, 190, 12, 4), with: .color(Theme.stroke))
                context.fill(ellipse(150, 178, 15, 4), with: .color(Self.cream))
                context.fill(ellipse(222, 178, 15, 4), with: .color(Self.cream))

                // Condiment shelf. Design centres this at y 108, which works in their 2.15:1
                // reference frame - but the live stage is nearer 2.46:1 with a proportionally
                // larger hanging sign, and at that ratio the sign covers y 46-137 exactly. Drawn
                // where design put it, this whole built-in was invisible. It sits instead in the
                // one clear band: below the sign, above where the queue's heads reach (y 189).
                fill(rr(330, 176, 180, 9, 3), Self.wood)
                stroke(Self.wood, 4) { path in
                    path.move(to: p(342, 185)); path.addLine(to: p(337, 196))
                    path.move(to: p(498, 185)); path.addLine(to: p(503, 196))
                }
                fill(rr(348, 148, 15, 28, 6), palette.counter)
                fill(rr(378, 150, 15, 26, 6), palette.accent)
                fill(rr(408, 157, 11, 19, 4), Self.cream)
                fill(rr(444, 162, 24, 14, 2), Self.cream)
                context.fill(rr(447, 154, 18, 9, 2), with: .color(Self.cream.opacity(0.85)))

                // Menu board.
                fill(rr(560, 66, 180, 124, 8), Self.hardware)
                context.fill(rr(572, 78, 156, 100, 4), with: .color(Color(hex: "#2E2A2B")))
                context.fill(rr(600, 86, 100, 9, 4), with: .color(palette.sign.opacity(0.85)))
                stroke(palette.sign, 5, opacity: 0.5) { path in
                    for (i, w) in [64.0, 56.0, 70.0, 48.0].enumerated() {
                        let y = 112 + Double(i) * 18
                        path.move(to: p(584, y)); path.addLine(to: p(584 + w, y))
                        path.move(to: p(672, y)); path.addLine(to: p(692, y))
                    }
                }

                // Bulb garland, at rest. Design sways this +/-1 degree; held for the motion pass.
                stroke(Theme.outline, 3) { path in
                    path.move(to: p(0, 22))
                    path.addQuadCurve(to: p(430, 32), control: p(215, 58))
                    path.addQuadCurve(to: p(860, 44), control: p(645, 6))
                }
                for (x, y, warm) in [(100.0, 34.0, true), (240.0, 47.0, false), (430.0, 32.0, true),
                                     (620.0, 14.0, true), (760.0, 26.0, false)] {
                    glowDot(x, y, 5, warm ? palette.accent : palette.sign)
                }

            case (.burger, .floor):
                // Skewed checker. A loop of parallelograms rather than a tiled image - about
                // forty quads, which is the whole floor.
                let tile: CGFloat = 52, skew: CGFloat = 14
                var checks = Path()
                for row in 0..<4 {
                    for col in 0..<18 {
                        guard (row + col) % 2 == 0 else { continue }
                        let y0 = 300 + CGFloat(row) * tile * 0.6
                        let y1 = y0 + tile * 0.6
                        let x0 = CGFloat(col) * tile - CGFloat(row) * skew
                        checks.move(to: p(x0, y0))
                        checks.addLine(to: p(x0 + tile, y0))
                        checks.addLine(to: p(x0 + tile - skew, y1))
                        checks.addLine(to: p(x0 - skew, y1))
                        checks.closeSubpath()
                    }
                }
                context.fill(checks, with: .color(.black.opacity(0.09)))

                // Pool of light landing centre-stage, where the VIP stands.
                context.fill(ellipse(430, 300, 90, 46), with: .radialGradient(
                    Gradient(colors: [palette.accent.opacity(0.18), .clear]),
                    center: p(430, 300), startRadius: 0, endRadius: 90 / 860 * rect.width))

            default:
                break
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
