import SwiftUI

/// Draws a station's food using only vector paths, so every item is crisp at any size and
/// the whole art set is editable code rather than binary assets.
///
/// `Equatable` matters here: the card that hosts this re-renders at the engine's 20Hz tick,
/// and without it SwiftUI re-ran the whole canvas every time for art that never changes.
/// `.drawingGroup()` made that worse by forcing an offscreen pass on each one.
struct FoodSprite: View, Equatable {
    let art: FoodArt
    let colors: [String]

    static func == (lhs: FoodSprite, rhs: FoodSprite) -> Bool {
        lhs.art == rhs.art && lhs.colors == rhs.colors
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.06,
                                                                 dy: size.height * 0.06)
            FoodArtRenderer.draw(art, in: rect, context: context, colors: resolved)
        }
        .accessibilityHidden(true)
    }

    private var resolved: FoodArtRenderer.Palette {
        let c = colors.map { Color(hex: $0) }
        return FoodArtRenderer.Palette(
            primary: c.count > 0 ? c[0] : Theme.coin,
            secondary: c.count > 1 ? c[1] : Theme.text,
            accent: c.count > 2 ? c[2] : Theme.negative
        )
    }
}

enum FoodArtRenderer {

    struct Palette {
        let primary: Color
        let secondary: Color
        let accent: Color
    }

    static func draw(_ art: FoodArt, in rect: CGRect, context: GraphicsContext, palette: Palette) {
        draw(art, in: rect, context: context, colors: palette)
    }

    static func draw(_ art: FoodArt, in rect: CGRect, context: GraphicsContext, colors: Palette) {
        let line = max(1.2, rect.width * 0.035)
        let outline = Color.black.opacity(0.28)

        // Unit-space helpers: every shape below is authored in a 0...1 box and mapped once.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                   width: w * rect.width, height: h * rect.height)
        }
        func fill(_ path: Path, _ color: Color, stroked: Bool = true) {
            context.fill(path, with: .color(color))
            if stroked { context.stroke(path, with: .color(outline), lineWidth: line) }
        }
        func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
            Path(roundedRect: r(x, y, w, h), cornerRadius: radius * rect.width)
        }
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            Path(ellipseIn: r(x, y, w, h))
        }
        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: p(first.0, first.1))
            for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
            path.closeSubpath()
            return path
        }

        switch art {

        case .fries:
            // Sticks first so the carton overlaps them.
            for (index, x) in [0.24, 0.38, 0.52, 0.66].enumerated() {
                let height: CGFloat = index % 2 == 0 ? 0.34 : 0.44
                fill(rounded(x, 0.52 - height, 0.11, height + 0.1, 0.03), colors.primary)
            }
            fill(polygon([(0.2, 0.46), (0.8, 0.46), (0.72, 0.94), (0.28, 0.94)]), colors.secondary)
            fill(rounded(0.31, 0.56, 0.38, 0.1, 0.02), colors.accent, stroked: false)

        case .bun:
            fill(polygon([(0.14, 0.44), (0.86, 0.44), (0.8, 0.3), (0.2, 0.3)]), colors.primary) // top bun body
            var dome = Path()
            dome.move(to: p(0.14, 0.44))
            dome.addQuadCurve(to: p(0.86, 0.44), control: p(0.5, 0.02))
            dome.closeSubpath()
            fill(dome, colors.primary)
            fill(rounded(0.12, 0.44, 0.76, 0.09, 0.03), colors.accent)              // lettuce
            fill(rounded(0.1, 0.52, 0.8, 0.13, 0.04), colors.secondary)             // patty
            var bottom = Path()
            bottom.move(to: p(0.14, 0.65))
            bottom.addLine(to: p(0.86, 0.65))
            bottom.addQuadCurve(to: p(0.14, 0.65), control: p(0.5, 0.98))
            fill(bottom, colors.primary)
            // Sesame seeds.
            for point in [(0.34, 0.24), (0.5, 0.18), (0.64, 0.25)] {
                context.fill(ellipse(point.0, point.1, 0.06, 0.04), with: .color(.white.opacity(0.8)))
            }

        case .cup:
            fill(polygon([(0.26, 0.28), (0.74, 0.28), (0.66, 0.94), (0.34, 0.94)]), colors.primary)
            fill(rounded(0.22, 0.2, 0.56, 0.1, 0.03), colors.secondary)             // lid
            fill(rounded(0.56, 0.02, 0.07, 0.24, 0.03), colors.accent)              // straw
            context.fill(polygon([(0.32, 0.46), (0.44, 0.46), (0.4, 0.86), (0.36, 0.86)]),
                         with: .color(.white.opacity(0.28)))

        case .stick:
            fill(rounded(0.44, 0.62, 0.12, 0.36, 0.04), colors.accent)              // handle
            fill(rounded(0.14, 0.24, 0.72, 0.4, 0.18), colors.primary)              // body
            var squiggle = Path()
            squiggle.move(to: p(0.22, 0.44))
            for i in 0..<5 {
                let x = 0.22 + CGFloat(i) * 0.14
                squiggle.addQuadCurve(to: p(x + 0.14, 0.44),
                                      control: p(x + 0.07, i % 2 == 0 ? 0.32 : 0.56))
            }
            context.stroke(squiggle, with: .color(colors.secondary), lineWidth: line * 1.8)

        case .cone:
            fill(polygon([(0.28, 0.5), (0.72, 0.5), (0.5, 0.97)]), colors.accent)   // cone
            fill(ellipse(0.24, 0.28, 0.34, 0.32), colors.primary)                   // scoops
            fill(ellipse(0.44, 0.24, 0.34, 0.32), colors.secondary)
            fill(ellipse(0.34, 0.08, 0.32, 0.3), colors.primary)

        case .plate:
            fill(ellipse(0.06, 0.6, 0.88, 0.3), Color.white.opacity(0.92))          // plate
            fill(ellipse(0.16, 0.66, 0.68, 0.17), Color.black.opacity(0.08), stroked: false)
            fill(ellipse(0.14, 0.34, 0.32, 0.32), colors.primary)                   // three items
            fill(ellipse(0.38, 0.26, 0.3, 0.34), colors.secondary)
            fill(ellipse(0.58, 0.36, 0.3, 0.3), colors.accent)

        case .bowl:
            fill(ellipse(0.12, 0.34, 0.76, 0.22), colors.secondary)                 // contents
            var bowl = Path()
            bowl.move(to: p(0.1, 0.44))
            bowl.addQuadCurve(to: p(0.9, 0.44), control: p(0.5, 1.06))
            bowl.closeSubpath()
            fill(bowl, colors.primary)
            fill(rounded(0.6, 0.06, 0.05, 0.42, 0.02), colors.accent)               // chopsticks
            fill(rounded(0.7, 0.04, 0.05, 0.42, 0.02), colors.accent)

        case .nigiri:
            fill(rounded(0.16, 0.52, 0.68, 0.3, 0.14), Color(hex: "#FBF5EA"))       // rice
            var fishTop = Path()
            fishTop.move(to: p(0.12, 0.56))
            fishTop.addQuadCurve(to: p(0.88, 0.56), control: p(0.5, 0.2))
            fishTop.addLine(to: p(0.84, 0.62))
            fishTop.addQuadCurve(to: p(0.16, 0.62), control: p(0.5, 0.32))
            fishTop.closeSubpath()
            fill(fishTop, colors.primary)
            fill(rounded(0.42, 0.4, 0.16, 0.44, 0.03), colors.accent)               // nori band

        case .roll:
            fill(ellipse(0.14, 0.18, 0.72, 0.72), colors.primary)                   // outer
            fill(ellipse(0.24, 0.28, 0.52, 0.52), colors.secondary)                 // rice
            fill(ellipse(0.38, 0.42, 0.24, 0.24), colors.accent)                    // centre
            for angle in stride(from: 0.0, to: 360.0, by: 60.0) {
                let rad = angle * .pi / 180
                let cx = 0.5 + 0.19 * cos(rad)
                let cy = 0.54 + 0.19 * sin(rad)
                context.fill(ellipse(cx - 0.045, cy - 0.045, 0.09, 0.09),
                             with: .color(colors.accent.opacity(0.55)))
            }

        case .wedge:
            fill(polygon([(0.5, 0.08), (0.94, 0.86), (0.06, 0.86)]), colors.primary)
            var crust = Path()
            crust.move(to: p(0.06, 0.86))
            crust.addLine(to: p(0.94, 0.86))
            crust.addQuadCurve(to: p(0.06, 0.86), control: p(0.5, 1.06))
            fill(crust, colors.secondary)
            for point in [(0.42, 0.38), (0.58, 0.55), (0.34, 0.64), (0.66, 0.7)] {
                context.fill(ellipse(point.0, point.1, 0.13, 0.11), with: .color(colors.accent))
            }

        case .wrap:
            var shell = Path()
            shell.move(to: p(0.08, 0.82))
            shell.addQuadCurve(to: p(0.92, 0.82), control: p(0.5, 0.06))
            shell.closeSubpath()
            fill(shell, colors.primary)
            var filling = Path()
            filling.move(to: p(0.2, 0.7))
            filling.addQuadCurve(to: p(0.8, 0.7), control: p(0.5, 0.36))
            filling.closeSubpath()
            fill(filling, colors.secondary, stroked: false)
            for point in [(0.3, 0.62), (0.46, 0.55), (0.62, 0.62)] {
                context.fill(ellipse(point.0, point.1, 0.12, 0.1), with: .color(colors.accent))
            }

        case .cupcake:
            fill(polygon([(0.24, 0.52), (0.76, 0.52), (0.68, 0.94), (0.32, 0.94)]), colors.accent)
            for x in stride(from: 0.3, to: 0.72, by: 0.1) {
                context.stroke(Path { path in
                    path.move(to: p(x, 0.54))
                    path.addLine(to: p(x - 0.02, 0.92))
                }, with: .color(.black.opacity(0.15)), lineWidth: line * 0.8)
            }
            fill(ellipse(0.16, 0.3, 0.68, 0.3), colors.primary)                     // frosting
            fill(ellipse(0.26, 0.14, 0.48, 0.26), colors.primary)
            fill(ellipse(0.42, 0.02, 0.18, 0.16), colors.secondary)                 // cherry
        }
    }
}
