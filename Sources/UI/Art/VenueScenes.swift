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
    static let rebuilt: Set<VenueTheme> = [.burger, .diner, .sushi]

    // Material colours. These are shared across every room on purpose - only *structural*
    // colour comes from `VenuePalette`, so the coin-priced neon skin stays a pure data change.
    private static let hardware = Color(hex: "#3A3346")
    private static let wood = Color(hex: "#5C4632")
    private static let cream = Color(hex: "#F2EDE2")
    private static let warmGlow = Color(hex: "#FFB84D")
    private static let nightSky = Color(hex: "#0A0F24")
    private static let nightHorizon = Color(hex: "#1B2547")
    private static let windowFrame = Color(hex: "#B9C2D9")

    // The string-light garland is byte-identical between Burger and Diner in design's own
    // reference (same positions, same five hex values) - it is warm bulbs on a physical wire,
    // not a neon fixture, so it does not follow the room's accent colour the way the rest of
    // the scene does. Kept as fixed constants rather than derived from `palette` so that stays
    // true instead of being an accident of Burger's accent happening to already be gold.
    private static let bulbGold = Color(hex: "#F5C242")
    private static let bulbCream = Color(hex: "#FFE9A8")
    private static let bulbRed = Color(hex: "#E4453A")

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
            /// Shared between Burger and Diner, per design - see the `bulb*` constants above.
            func warmGarland() {
                stroke(Theme.outline, 3) { path in
                    path.move(to: p(0, 22))
                    path.addQuadCurve(to: p(430, 32), control: p(215, 58))
                    path.addQuadCurve(to: p(860, 44), control: p(645, 6))
                }
                let bulbs: [(CGFloat, CGFloat, Color)] = [
                    (100, 34, Self.bulbGold), (240, 47, Self.bulbCream), (430, 32, Self.bulbRed),
                    (620, 14, Self.bulbGold), (760, 26, Self.bulbCream),
                ]
                for (x, y, color) in bulbs { glowDot(x, y, 5, color) }
            }
            /// A paper lantern on its own drop cord, glow included.
            func lantern(_ cx: CGFloat, _ cy: CGFloat, _ color: Color) {
                stroke(Theme.outline, 2.5) { path in
                    path.move(to: p(cx, 0)); path.addLine(to: p(cx, cy - 24))
                }
                context.fill(ellipse(cx, cy, 30, 30), with: .color(color.opacity(0.16)))
                fill(ellipse(cx, cy, 17, 22), color)
                stroke(Theme.outline, 1.5, opacity: 0.4) { path in
                    path.move(to: p(cx - 15, cy - 7))
                    path.addQuadCurve(to: p(cx + 15, cy - 7), control: p(cx, cy - 1))
                    path.move(to: p(cx - 15, cy + 7))
                    path.addQuadCurve(to: p(cx + 15, cy + 7), control: p(cx, cy + 13))
                }
                context.fill(rr(cx - 6, cy - 26, 12, 5, 2), with: .color(Theme.outline))
                context.fill(rr(cx - 6, cy + 21, 12, 5, 2), with: .color(Theme.outline))
            }
            /// A skewed checkerboard built from ~70 parallelograms rather than a tiled image.
            func checkerFloor(_ color: Color, opacity: Double) {
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
                context.fill(checks, with: .color(color.opacity(opacity)))
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
                warmGarland()

            case (.burger, .floor):
                checkerFloor(.black, opacity: 0.09)

                // Pool of light landing centre-stage, where the VIP stands.
                context.fill(ellipse(430, 300, 90, 46), with: .radialGradient(
                    Gradient(colors: [palette.accent.opacity(0.18), .clear]),
                    center: p(430, 300), startRadius: 0, endRadius: 90 / 860 * rect.width))

            case (.diner, .wall):
                // Same panel seams and courses as Burger - the two rooms share this bone
                // structure in design's reference, only the dressing on top differs.
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
                context.fill(Path(box(0, 236, 860, 64)), with: .color(palette.wallBottom))
                context.fill(Path(box(0, 236, 860, 64)), with: .color(.white.opacity(0.06)))
                stroke(palette.wallBottom, 2.5, opacity: 0.6) { path in
                    for i in 0..<9 {
                        let x = 70 + Double(i) * 100
                        path.move(to: p(x, 236)); path.addLine(to: p(x, 300))
                    }
                }
                // Neon trim, not a plain accent line: a bright hairline sitting inside a wider,
                // soft halo - the glow-stroke pairing design calls for at the wainscot edge.
                context.fill(Path(box(0, 228, 860, 9)), with: .color(palette.accent.opacity(0.16)))
                context.fill(Path(box(0, 231, 860, 3)), with: .color(palette.accent.opacity(0.75)))

                // Night window: sky, moon, stars and a skyline silhouette - the room's own
                // second light source is neon rather than a kitchen glow, so this window stays
                // cool and dark instead of warm and lit. Narrowed to x100-280 (design called for
                // 100-300): the hanging sign's real rendered width reaches to about x285 on this
                // stage, wider than design's own reference frame assumed - see the Burger
                // condiment-shelf note below for the same shape of problem. Full width would
                // have tucked 15 units of the window's right edge under the sign.
                fill(rr(100, 66, 180, 120, 10), Self.windowFrame)
                context.fill(rr(112, 78, 156, 96, 5), with: .linearGradient(
                    Gradient(colors: [Self.nightSky, Self.nightHorizon]),
                    startPoint: p(190, 78), endPoint: p(190, 174)))
                context.fill(ellipse(230, 102, 14, 14), with: .color(Color(hex: "#E6F0FF").opacity(0.9)))
                context.fill(ellipse(224, 98, 12, 12), with: .color(Self.nightSky))
                for (x, y, r) in [(130.0, 96.0, 1.6), (155.0, 88.0, 1.3), (195.0, 100.0, 1.5),
                                  (148.0, 112.0, 1.2), (208.0, 86.0, 1.2)] {
                    context.fill(ellipse(x, y, r, r), with: .color(Color(hex: "#E6F0FF")))
                }
                // Skyline: flat black reads as a true silhouette against the gradient sky behind
                // it, where the near-identical `nightSky` fill used in the first pass didn't.
                var skyline = Path()
                skyline.move(to: p(112, 174))
                skyline.addLine(to: p(112, 140)); skyline.addLine(to: p(128, 140))
                skyline.addLine(to: p(128, 126)); skyline.addLine(to: p(142, 126))
                skyline.addLine(to: p(142, 148)); skyline.addLine(to: p(160, 148))
                skyline.addLine(to: p(160, 118)); skyline.addLine(to: p(176, 118))
                skyline.addLine(to: p(176, 160)); skyline.addLine(to: p(196, 160))
                skyline.addLine(to: p(196, 134)); skyline.addLine(to: p(210, 134))
                skyline.addLine(to: p(210, 174))
                skyline.closeSubpath()
                context.fill(skyline, with: .color(.black))
                for (x, y) in [(126.0, 136.0), (158.0, 142.0), (180.0, 152.0)] {
                    context.fill(rr(x, y, 4, 4, 0), with: .color(Theme.coin.opacity(0.7)))
                }

                // Jukebox. A real free-standing cabinet needs to reach the floor to look
                // grounded, but the live queue's heads reach up to about y190 - well below where
                // design's own mockup assumed a mostly-empty floor. Anything that used to poke
                // above that line (the neon arch peaked at y144) read as a hood on whichever
                // customer happened to be standing in that slot, which given the queue's fixed
                // spacing was nearly every customer, nearly every time. Compressed to sit
                // entirely at or below head height instead: still grounded, still lit, but now
                // it's furniture behind the queue rather than a hat on it.
                fill(rr(346, 205, 84, 95, 12), Theme.stroke)
                context.fill(ellipse(388, 255, 30, 45), with: .color(palette.accent.opacity(0.16)))
                stroke(palette.accent, 4) { path in
                    path.move(to: p(356, 270)); path.addLine(to: p(356, 240))
                    path.addQuadCurve(to: p(420, 240), control: p(356, 212))
                    path.addLine(to: p(420, 270))
                }
                context.fill(rr(362, 216, 52, 20, 4), with: .color(Color(hex: "#D8E6FF").opacity(0.85)))
                stroke(palette.counterEdge, 2) { path in
                    for (i, w) in [40.0, 40.0, 28.0].enumerated() {
                        let y = 221 + Double(i) * 5
                        path.move(to: p(368, y)); path.addLine(to: p(368 + w, y))
                    }
                }
                context.fill(rr(362, 242, 52, 50, 5), with: .color(Color(hex: "#2E2A2B")))
                context.fill(ellipse(376, 264, 6, 6), with: .color(palette.accent.opacity(0.8)))
                context.fill(ellipse(400, 264, 6, 6), with: .color(Theme.gem.opacity(0.8)))

                // Neon wall clock, parked with its hands at rest. Moved from design's x490 (dead
                // centre of the hanging sign, and entirely hidden behind it) to the gap left of
                // the window - the sign's rendered width covers roughly x285-571 here, wider
                // than the ~x350-610 design's own frame implied, so x490 was never visible.
                context.fill(ellipse(50, 120, 30.5, 30.5), with: .color(palette.accent.opacity(0.18)))
                stroke(palette.accent, 4) { path in path.addEllipse(in: box(50 - 27, 120 - 27, 54, 54)) }
                context.fill(ellipse(50, 120, 20, 20), with: .color(palette.wallBottom))
                stroke(Color(hex: "#E6F0FF"), 2.5) { path in
                    path.move(to: p(50, 108)); path.addLine(to: p(50, 120)); path.addLine(to: p(58, 126))
                }

                // Menu board - identical build to Burger's, only the interior tint changes.
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

                warmGarland()

            case (.diner, .floor):
                // "The bold checkerboard the brief says this room earns" - design's own words;
                // a stronger tint than Burger's subtle version, not the same opacity reused.
                checkerFloor(.black, opacity: 0.16)
                context.fill(ellipse(430, 300, 90, 46), with: .radialGradient(
                    Gradient(colors: [palette.accent.opacity(0.16), .clear]),
                    center: p(430, 300), startRadius: 0, endRadius: 90 / 860 * rect.width))

            case (.sushi, .wall):
                // Panel seams, courses and wainscot - same bones as Burger/Diner, per design.
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
                context.fill(Path(box(0, 236, 860, 64)), with: .color(palette.wallBottom))
                context.fill(Path(box(0, 236, 860, 64)), with: .color(.white.opacity(0.06)))
                stroke(palette.wallBottom, 2.5, opacity: 0.6) { path in
                    for i in 0..<9 {
                        let x = 70 + Double(i) * 100
                        path.move(to: p(x, 236)); path.addLine(to: p(x, 300))
                    }
                }
                context.fill(Path(box(0, 232, 860, 4)), with: .color(palette.accent.opacity(0.3)))

                // Sake and bowl cubby shelf. Stays under x270, well clear of the sign's
                // real x285-571 span - the same safe zone the Burger condiment shelf uses.
                fill(rr(90, 66, 180, 124, 8), palette.floor)
                stroke(Theme.outline, 2, opacity: 0.35) { path in
                    path.move(to: p(90, 128)); path.addLine(to: p(270, 128))
                    path.move(to: p(150, 66)); path.addLine(to: p(150, 190))
                    path.move(to: p(210, 66)); path.addLine(to: p(210, 190))
                }
                fill(rr(104, 92, 16, 34, 6), Self.cream)
                fill(rr(126, 98, 14, 28, 5), palette.counter)
                fill(ellipse(180, 112, 16, 7), palette.accent)
                fill(ellipse(180, 104, 13, 6), Self.cream)
                fill(rr(222, 140, 34, 40, 4), Self.wood)
                fill(ellipse(130, 160, 18, 8), Self.cream)

                // Menu board - identical build to Burger and Diner.
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

                // Three paper lanterns replace the bulb garland - design's call, per §6.4 - and
                // they stay well above y150, clear of the queue the same way the window and
                // clock do in the other two rooms.
                lantern(180, 76, palette.accent)
                lantern(560, 70, Self.cream)
                lantern(680, 80, palette.accent)

            case (.sushi, .floor):
                // Tatami bands: two straight joints, quieter than a checker or tile grid.
                stroke(Self.wood, 2, opacity: 0.35) { path in
                    path.move(to: p(0, 332)); path.addLine(to: p(860, 332))
                    path.move(to: p(0, 366)); path.addLine(to: p(860, 366))
                }
                context.fill(ellipse(430, 300, 90, 46), with: .radialGradient(
                    Gradient(colors: [palette.accent.opacity(0.14), .clear]),
                    center: p(430, 300), startRadius: 0, endRadius: 90 / 860 * rect.width))

            default:
                break
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
