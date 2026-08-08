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

/// Transcribed from the visual-refresh asset pack's `food-*.svg` set (100-unit viewBox,
/// `PRIMARY`/`SECONDARY`/`ACCENT` fill slots, one shared `OUTLINE`). Every coordinate below
/// is the SVG's own, divided by 100 into this file's existing 0...1 unit box.
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
        // The asset pack's OUTLINE spec: a single solid dark line at ~4 units on the
        // 100-unit box, not the softer partial-opacity line this file used before.
        let line = max(1.2, rect.width * 0.045)
        let outline = Color(hex: "#2B1D14")
        let shade = outline.opacity(0.13)
        let shadowColor = outline.opacity(0.18)
        let gloss = Color.white

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                   width: w * rect.width, height: h * rect.height)
        }
        func w(_ v: CGFloat) -> CGFloat { rect.width * v / 100 }
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
        func rotated(_ path: Path, _ angle: Double, _ ax: CGFloat, _ ay: CGFloat) -> Path {
            let pivot = p(ax, ay)
            var t = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            t = t.rotated(by: angle * .pi / 180)
            t = t.translatedBy(x: -pivot.x, y: -pivot.y)
            return path.applying(t)
        }
        func custom(_ build: (inout Path) -> Void) -> Path {
            var path = Path()
            build(&path)
            return path
        }
        func groundShadow(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
            context.fill(ellipse(cx - rx, cy - ry, rx * 2, ry * 2), with: .color(shadowColor))
        }
        func overlay(_ path: Path, _ color: Color) {
            context.fill(path, with: .color(color))
        }
        func openStroke(_ color: Color, width: CGFloat, opacity: Double = 1,
                        _ build: (inout Path) -> Void) {
            context.stroke(custom(build), with: .color(color.opacity(opacity)), lineWidth: width)
        }

        switch art {

        case .fries:
            groundShadow(0.5, 0.93, 0.27, 0.05)
            for (cx, cy, angle) in [(0.375, 0.48, -9.0), (0.445, 0.435, -3.0),
                                    (0.565, 0.45, 4.0), (0.675, 0.50, 11.0)] {
                fill(rotated(rounded(cx - 0.055, cy - 0.23, 0.11, 0.46, 0.03), angle, cx, cy),
                     colors.primary)
            }
            fill(custom { path in
                path.move(to: p(0.27, 0.50)); path.addLine(to: p(0.73, 0.50))
                path.addLine(to: p(0.67, 0.86))
                path.addQuadCurve(to: p(0.62, 0.90), control: p(0.66, 0.90))
                path.addLine(to: p(0.38, 0.90))
                path.addQuadCurve(to: p(0.33, 0.86), control: p(0.34, 0.90))
                path.closeSubpath()
            }, colors.secondary)
            overlay(custom { path in
                path.move(to: p(0.30, 0.62)); path.addLine(to: p(0.70, 0.62))
                path.addLine(to: p(0.684, 0.75)); path.addLine(to: p(0.316, 0.75))
                path.closeSubpath()
            }, colors.accent)
            overlay(custom { path in
                path.move(to: p(0.64, 0.52)); path.addLine(to: p(0.69, 0.52))
                path.addLine(to: p(0.64, 0.88))
                path.addQuadCurve(to: p(0.62, 0.90), control: p(0.68, 0.90))
                path.addLine(to: p(0.57, 0.90)); path.closeSubpath()
            }, shade)
            overlay(custom { path in
                path.move(to: p(0.35, 0.54)); path.addLine(to: p(0.41, 0.54))
                path.addLine(to: p(0.38, 0.85))
                path.addQuadCurve(to: p(0.346, 0.81), control: p(0.35, 0.84))
                path.closeSubpath()
            }, gloss.opacity(0.28))

        case .bun:
            groundShadow(0.5, 0.93, 0.31, 0.05)
            fill(custom { path in
                path.move(to: p(0.20, 0.74)); path.addLine(to: p(0.80, 0.74))
                path.addLine(to: p(0.80, 0.80))
                path.addQuadCurve(to: p(0.68, 0.90), control: p(0.80, 0.90))
                path.addLine(to: p(0.32, 0.90))
                path.addQuadCurve(to: p(0.20, 0.80), control: p(0.20, 0.90))
                path.closeSubpath()
            }, colors.primary)
            fill(rounded(0.16, 0.61, 0.68, 0.15, 0.07), colors.secondary)
            fill(custom { path in
                path.move(to: p(0.15, 0.52)); path.addLine(to: p(0.85, 0.52))
                path.addLine(to: p(0.85, 0.58))
                path.addQuadCurve(to: p(0.73, 0.58), control: p(0.79, 0.67))
                path.addQuadCurve(to: p(0.61, 0.58), control: p(0.67, 0.67))
                path.addQuadCurve(to: p(0.49, 0.58), control: p(0.55, 0.67))
                path.addQuadCurve(to: p(0.37, 0.58), control: p(0.43, 0.67))
                path.addQuadCurve(to: p(0.25, 0.58), control: p(0.31, 0.67))
                path.addQuadCurve(to: p(0.15, 0.58), control: p(0.17, 0.66))
                path.closeSubpath()
            }, colors.accent)
            fill(custom { path in
                path.move(to: p(0.18, 0.54))
                path.addQuadCurve(to: p(0.50, 0.21), control: p(0.18, 0.21))
                path.addQuadCurve(to: p(0.82, 0.54), control: p(0.82, 0.21))
                path.closeSubpath()
            }, colors.primary)
            overlay(custom { path in
                path.move(to: p(0.62, 0.24))
                path.addQuadCurve(to: p(0.82, 0.54), control: p(0.82, 0.32))
                path.addLine(to: p(0.70, 0.54))
                path.addQuadCurve(to: p(0.58, 0.23), control: p(0.70, 0.32))
                path.closeSubpath()
            }, shade)
            overlay(rotated(ellipse(0.245, 0.28, 0.26, 0.14), -28, 0.37, 0.35), gloss.opacity(0.3))
            for (cx, cy, angle) in [(0.41, 0.33, -18.0), (0.53, 0.28, 6.0), (0.64, 0.36, 22.0)] {
                overlay(rotated(ellipse(cx - 0.034, cy - 0.021, 0.068, 0.042), angle, cx, cy),
                       gloss.opacity(0.75))
            }
            overlay(custom { path in
                path.move(to: p(0.24, 0.84))
                path.addQuadCurve(to: p(0.76, 0.84), control: p(0.50, 0.90))
                path.addQuadCurve(to: p(0.68, 0.90), control: p(0.74, 0.90))
                path.addLine(to: p(0.32, 0.90))
                path.addQuadCurve(to: p(0.24, 0.84), control: p(0.26, 0.90))
                path.closeSubpath()
            }, shade)

        case .cup:
            groundShadow(0.5, 0.93, 0.24, 0.05)
            fill(custom { path in
                path.move(to: p(0.31, 0.40)); path.addLine(to: p(0.69, 0.40))
                path.addLine(to: p(0.64, 0.86))
                path.addQuadCurve(to: p(0.59, 0.90), control: p(0.63, 0.90))
                path.addLine(to: p(0.41, 0.90))
                path.addQuadCurve(to: p(0.36, 0.86), control: p(0.37, 0.90))
                path.closeSubpath()
            }, colors.primary)
            overlay(custom { path in
                path.move(to: p(0.55, 0.42)); path.addLine(to: p(0.64, 0.42))
                path.addLine(to: p(0.59, 0.88))
                path.addQuadCurve(to: p(0.59, 0.90), control: p(0.63, 0.90))
                path.addLine(to: p(0.50, 0.90)); path.closeSubpath()
            }, shade)
            overlay(custom { path in
                path.move(to: p(0.34, 0.58)); path.addLine(to: p(0.66, 0.58))
                path.addLine(to: p(0.646, 0.70)); path.addLine(to: p(0.354, 0.70))
                path.closeSubpath()
            }, colors.accent)
            fill(rotated(rounded(0.56, 0.06, 0.09, 0.27, 0.04), 16, 0.60, 0.20), colors.accent)
            fill(rounded(0.26, 0.30, 0.48, 0.11, 0.05), colors.secondary)
            overlay(custom { path in
                path.move(to: p(0.40, 0.46)); path.addLine(to: p(0.46, 0.46))
                path.addLine(to: p(0.42, 0.82))
                path.addQuadCurve(to: p(0.385, 0.78), control: p(0.39, 0.81))
                path.closeSubpath()
            }, gloss.opacity(0.32))

        case .stick:
            groundShadow(0.5, 0.95, 0.15, 0.04)
            fill(rounded(0.45, 0.60, 0.10, 0.33, 0.05), colors.secondary)
            fill(rounded(0.30, 0.10, 0.40, 0.58, 0.20), colors.primary)
            overlay(custom { path in
                path.move(to: p(0.58, 0.13))
                path.addQuadCurve(to: p(0.70, 0.30), control: p(0.70, 0.20))
                path.addLine(to: p(0.70, 0.48))
                path.addQuadCurve(to: p(0.58, 0.65), control: p(0.70, 0.58))
                path.addQuadCurve(to: p(0.66, 0.44), control: p(0.66, 0.56))
                path.addLine(to: p(0.66, 0.30))
                path.addQuadCurve(to: p(0.58, 0.13), control: p(0.66, 0.20))
                path.closeSubpath()
            }, shade)
            for (fromY, toY) in [(0.25, 0.23), (0.39, 0.37), (0.53, 0.51)] {
                openStroke(colors.accent, width: w(5)) { path in
                    path.move(to: p(0.37, fromY))
                    path.addQuadCurve(to: p(0.63, toY), control: p(0.50, fromY + 0.08))
                }
            }
            overlay(rotated(ellipse(0.34, 0.17, 0.10, 0.26), -6, 0.39, 0.30), gloss.opacity(0.26))

        case .cone:
            groundShadow(0.5, 0.95, 0.16, 0.04)
            fill(custom { path in
                path.move(to: p(0.30, 0.50)); path.addLine(to: p(0.70, 0.50))
                path.addLine(to: p(0.53, 0.90))
                path.addQuadCurve(to: p(0.47, 0.90), control: p(0.50, 0.95))
                path.closeSubpath()
            }, colors.secondary)
            overlay(custom { path in
                path.move(to: p(0.56, 0.52)); path.addLine(to: p(0.70, 0.52))
                path.addLine(to: p(0.53, 0.90))
                path.addQuadCurve(to: p(0.47, 0.90), control: p(0.50, 0.95))
                path.addLine(to: p(0.49, 0.86)); path.closeSubpath()
            }, shade)
            openStroke(gloss, width: w(2.4), opacity: 0.24) { path in
                path.move(to: p(0.36, 0.60)); path.addLine(to: p(0.60, 0.53))
            }
            openStroke(gloss, width: w(2.4), opacity: 0.24) { path in
                path.move(to: p(0.40, 0.71)); path.addLine(to: p(0.64, 0.62))
            }
            openStroke(gloss, width: w(2.4), opacity: 0.24) { path in
                path.move(to: p(0.34, 0.55)); path.addLine(to: p(0.44, 0.78))
            }
            fill(ellipse(0.28, 0.25, 0.44, 0.44), colors.primary)
            fill(ellipse(0.35, 0.09, 0.30, 0.30), colors.accent)
            overlay(rotated(ellipse(0.30, 0.355, 0.16, 0.09), -28, 0.38, 0.40), gloss.opacity(0.3))
            overlay(rotated(ellipse(0.36, 0.146, 0.12, 0.068), -32, 0.42, 0.18), gloss.opacity(0.34))
            overlay(custom { path in
                path.move(to: p(0.60, 0.12))
                path.addQuadCurve(to: p(0.65, 0.27), control: p(0.66, 0.18))
                path.addQuadCurve(to: p(0.63, 0.12), control: p(0.71, 0.20))
                path.closeSubpath()
            }, gloss.opacity(0.14))

        case .plate:
            groundShadow(0.5, 0.90, 0.38, 0.06)
            fill(ellipse(0.08, 0.61, 0.84, 0.26), colors.secondary)
            overlay(ellipse(0.19, 0.65, 0.62, 0.16), gloss.opacity(0.18))
            fill(custom { path in
                path.move(to: p(0.19, 0.70))
                path.addQuadCurve(to: p(0.32, 0.50), control: p(0.19, 0.50))
                path.addQuadCurve(to: p(0.45, 0.70), control: p(0.45, 0.50))
                path.closeSubpath()
            }, colors.primary)
            overlay(rounded(0.20, 0.60, 0.24, 0.07, 0.035), colors.accent)
            fill(custom { path in
                path.move(to: p(0.53, 0.70)); path.addLine(to: p(0.61, 0.46))
                path.addQuadCurve(to: p(0.64, 0.46), control: p(0.625, 0.425))
                path.addLine(to: p(0.73, 0.70)); path.closeSubpath()
            }, colors.accent)
            fill(ellipse(0.75, 0.57, 0.14, 0.14), colors.primary)
            fill(ellipse(0.82, 0.64, 0.12, 0.12), colors.primary)
            fill(custom { path in
                path.move(to: p(0.09, 0.76))
                path.addQuadCurve(to: p(0.91, 0.76), control: p(0.50, 0.92))
                path.addQuadCurve(to: p(0.09, 0.76), control: p(0.50, 0.87))
                path.closeSubpath()
            }, colors.secondary)
            overlay(custom { path in
                path.move(to: p(0.20, 0.80))
                path.addQuadCurve(to: p(0.80, 0.80), control: p(0.50, 0.90))
                path.addQuadCurve(to: p(0.20, 0.80), control: p(0.50, 0.87))
                path.closeSubpath()
            }, shade)
            overlay(rotated(ellipse(0.15, 0.728, 0.22, 0.064), -7, 0.26, 0.76), gloss.opacity(0.24))
            overlay(rotated(ellipse(0.29, 0.54, 0.10, 0.06), -30, 0.34, 0.57), gloss.opacity(0.3))

        case .bowl:
            groundShadow(0.5, 0.93, 0.28, 0.05)
            openStroke(gloss, width: w(4), opacity: 0.4) { path in
                path.move(to: p(0.40, 0.32))
                path.addQuadCurve(to: p(0.40, 0.16), control: p(0.47, 0.25))
            }
            openStroke(gloss, width: w(4), opacity: 0.4) { path in
                path.move(to: p(0.58, 0.30))
                path.addQuadCurve(to: p(0.58, 0.14), control: p(0.65, 0.23))
            }
            fill(ellipse(0.20, 0.41, 0.60, 0.18), colors.secondary)
            fill(ellipse(0.32, 0.40, 0.12, 0.12), colors.accent)
            fill(ellipse(0.53, 0.39, 0.12, 0.12), colors.accent)
            fill(custom { path in
                path.move(to: p(0.18, 0.48)); path.addLine(to: p(0.82, 0.48))
                path.addQuadCurve(to: p(0.50, 0.86), control: p(0.80, 0.86))
                path.addQuadCurve(to: p(0.18, 0.48), control: p(0.20, 0.86))
                path.closeSubpath()
            }, colors.primary)
            overlay(custom { path in
                path.move(to: p(0.64, 0.50)); path.addLine(to: p(0.82, 0.50))
                path.addQuadCurve(to: p(0.50, 0.86), control: p(0.80, 0.86))
                path.addQuadCurve(to: p(0.70, 0.50), control: p(0.68, 0.82))
                path.closeSubpath()
            }, shade)
            overlay(custom { path in
                path.move(to: p(0.18, 0.48)); path.addLine(to: p(0.82, 0.48))
                path.addQuadCurve(to: p(0.81, 0.57), control: p(0.816, 0.53))
                path.addLine(to: p(0.19, 0.57))
                path.addQuadCurve(to: p(0.18, 0.48), control: p(0.184, 0.53))
                path.closeSubpath()
            }, gloss.opacity(0.18))
            openStroke(gloss, width: w(6), opacity: 0.24) { path in
                path.move(to: p(0.27, 0.58))
                path.addQuadCurve(to: p(0.39, 0.81), control: p(0.30, 0.74))
            }
            fill(rotated(rounded(0.63, 0.12, 0.06, 0.50, 0.03), 17, 0.66, 0.37), colors.secondary)
            fill(rotated(rounded(0.70, 0.12, 0.06, 0.50, 0.03), 26, 0.73, 0.37), colors.secondary)

        case .nigiri:
            groundShadow(0.5, 0.88, 0.32, 0.05)
            fill(custom { path in
                path.move(to: p(0.22, 0.58))
                path.addQuadCurve(to: p(0.33, 0.48), control: p(0.22, 0.48))
                path.addLine(to: p(0.67, 0.48))
                path.addQuadCurve(to: p(0.78, 0.58), control: p(0.78, 0.48))
                path.addLine(to: p(0.78, 0.68))
                path.addQuadCurve(to: p(0.62, 0.82), control: p(0.78, 0.82))
                path.addLine(to: p(0.38, 0.82))
                path.addQuadCurve(to: p(0.22, 0.68), control: p(0.22, 0.82))
                path.closeSubpath()
            }, colors.primary)
            overlay(custom { path in
                path.move(to: p(0.66, 0.50))
                path.addQuadCurve(to: p(0.78, 0.60), control: p(0.78, 0.52))
                path.addLine(to: p(0.78, 0.68))
                path.addQuadCurve(to: p(0.62, 0.82), control: p(0.78, 0.82))
                path.addLine(to: p(0.50, 0.82))
                path.addQuadCurve(to: p(0.68, 0.64), control: p(0.68, 0.78))
                path.closeSubpath()
            }, shade)
            fill(custom { path in
                path.move(to: p(0.16, 0.52))
                path.addQuadCurve(to: p(0.50, 0.31), control: p(0.16, 0.33))
                path.addQuadCurve(to: p(0.84, 0.52), control: p(0.84, 0.33))
                path.addQuadCurve(to: p(0.76, 0.58), control: p(0.84, 0.58))
                path.addLine(to: p(0.24, 0.58))
                path.addQuadCurve(to: p(0.16, 0.52), control: p(0.16, 0.58))
                path.closeSubpath()
            }, colors.secondary)
            openStroke(gloss, width: w(3.6), opacity: 0.3) { path in
                path.move(to: p(0.25, 0.45))
                path.addQuadCurve(to: p(0.75, 0.45), control: p(0.50, 0.39))
            }
            openStroke(gloss, width: w(3.6), opacity: 0.3) { path in
                path.move(to: p(0.30, 0.53))
                path.addQuadCurve(to: p(0.70, 0.53), control: p(0.50, 0.48))
            }
            fill(rounded(0.42, 0.30, 0.16, 0.54, 0.03), colors.accent)
            overlay(rotated(ellipse(0.275, 0.40, 0.09, 0.04), -12, 0.32, 0.42), gloss.opacity(0.26))

        case .roll:
            groundShadow(0.5, 0.90, 0.30, 0.05)
            fill(ellipse(0.16, 0.18, 0.68, 0.68), colors.accent)
            fill(ellipse(0.25, 0.27, 0.50, 0.50), colors.primary)
            fill(ellipse(0.35, 0.39, 0.18, 0.18), colors.secondary)
            fill(ellipse(0.50, 0.51, 0.14, 0.14), colors.secondary)
            fill(ellipse(0.51, 0.38, 0.10, 0.10), colors.accent)
            overlay(custom { path in
                path.move(to: p(0.20, 0.60))
                path.addQuadCurve(to: p(0.50, 0.84), control: p(0.30, 0.84))
                path.addQuadCurve(to: p(0.80, 0.60), control: p(0.72, 0.84))
                path.addQuadCurve(to: p(0.50, 0.86), control: p(0.78, 0.86))
                path.addQuadCurve(to: p(0.20, 0.60), control: p(0.22, 0.86))
                path.closeSubpath()
            }, shade)
            overlay(rotated(ellipse(0.24, 0.28, 0.22, 0.12), -38, 0.35, 0.34), gloss.opacity(0.24))

        case .wedge:
            groundShadow(0.5, 0.93, 0.30, 0.05)
            fill(custom { path in
                path.move(to: p(0.48, 0.12))
                path.addQuadCurve(to: p(0.52, 0.12), control: p(0.50, 0.08))
                path.addLine(to: p(0.80, 0.76))
                path.addQuadCurve(to: p(0.20, 0.76), control: p(0.50, 0.88))
                path.closeSubpath()
            }, colors.primary)
            overlay(custom { path in
                path.move(to: p(0.52, 0.12)); path.addLine(to: p(0.80, 0.76))
                path.addQuadCurve(to: p(0.56, 0.826), control: p(0.66, 0.816))
                path.addLine(to: p(0.52, 0.12)); path.closeSubpath()
            }, shade)
            fill(custom { path in
                path.move(to: p(0.20, 0.76))
                path.addQuadCurve(to: p(0.80, 0.76), control: p(0.50, 0.88))
                path.addLine(to: p(0.77, 0.85))
                path.addQuadCurve(to: p(0.23, 0.85), control: p(0.50, 0.97))
                path.closeSubpath()
            }, colors.secondary)
            fill(ellipse(0.355, 0.395, 0.13, 0.13), colors.accent)
            fill(ellipse(0.505, 0.525, 0.13, 0.13), colors.accent)
            fill(ellipse(0.35, 0.61, 0.12, 0.12), colors.accent)
            overlay(custom { path in
                path.move(to: p(0.47, 0.22)); path.addLine(to: p(0.52, 0.22))
                path.addLine(to: p(0.46, 0.46))
                path.addQuadCurve(to: p(0.425, 0.40), control: p(0.425, 0.44))
                path.closeSubpath()
            }, gloss.opacity(0.26))

        case .wrap:
            groundShadow(0.5, 0.90, 0.34, 0.045)
            fill(custom { path in
                path.move(to: p(0.14, 0.34))
                path.addQuadCurve(to: p(0.28, 0.32), control: p(0.18, 0.26))
                path.addQuadCurve(to: p(0.50, 0.27), control: p(0.38, 0.15))
                path.addQuadCurve(to: p(0.72, 0.32), control: p(0.62, 0.15))
                path.addQuadCurve(to: p(0.86, 0.34), control: p(0.82, 0.26))
                path.addQuadCurve(to: p(0.50, 0.66), control: p(0.80, 0.66))
                path.addQuadCurve(to: p(0.14, 0.34), control: p(0.20, 0.66))
                path.closeSubpath()
            }, colors.accent)
            fill(ellipse(0.23, 0.27, 0.14, 0.14), colors.secondary)
            fill(ellipse(0.43, 0.19, 0.14, 0.14), colors.secondary)
            fill(ellipse(0.63, 0.27, 0.14, 0.14), colors.secondary)
            fill(custom { path in
                path.move(to: p(0.12, 0.32))
                path.addQuadCurve(to: p(0.50, 0.86), control: p(0.16, 0.86))
                path.addQuadCurve(to: p(0.88, 0.32), control: p(0.84, 0.86))
                path.addQuadCurve(to: p(0.50, 0.68), control: p(0.84, 0.68))
                path.addQuadCurve(to: p(0.12, 0.32), control: p(0.16, 0.68))
                path.closeSubpath()
            }, colors.primary)
            overlay(custom { path in
                path.move(to: p(0.14, 0.42))
                path.addQuadCurve(to: p(0.50, 0.68), control: p(0.18, 0.68))
                path.addQuadCurve(to: p(0.86, 0.42), control: p(0.82, 0.68))
                path.addQuadCurve(to: p(0.50, 0.61), control: p(0.80, 0.61))
                path.addQuadCurve(to: p(0.14, 0.42), control: p(0.20, 0.61))
                path.closeSubpath()
            }, colors.secondary)
            overlay(custom { path in
                path.move(to: p(0.88, 0.32))
                path.addQuadCurve(to: p(0.50, 0.86), control: p(0.84, 0.86))
                path.addQuadCurve(to: p(0.77, 0.44), control: p(0.72, 0.79))
                path.closeSubpath()
            }, shade)
            openStroke(gloss, width: w(6), opacity: 0.26) { path in
                path.move(to: p(0.20, 0.48))
                path.addQuadCurve(to: p(0.38, 0.82), control: p(0.24, 0.74))
            }

        case .cupcake:
            groundShadow(0.5, 0.95, 0.26, 0.045)
            fill(custom { path in
                path.move(to: p(0.28, 0.52)); path.addLine(to: p(0.72, 0.52))
                path.addLine(to: p(0.66, 0.88))
                path.addQuadCurve(to: p(0.61, 0.92), control: p(0.65, 0.92))
                path.addLine(to: p(0.39, 0.92))
                path.addQuadCurve(to: p(0.34, 0.88), control: p(0.35, 0.92))
                path.closeSubpath()
            }, colors.secondary)
            for x in stride(from: 0.42, through: 0.58, by: 0.08) {
                openStroke(outline, width: w(3), opacity: 0.14) { path in
                    path.move(to: p(x, 0.56))
                    path.addLine(to: p(x - 0.01, 0.90))
                }
            }
            overlay(custom { path in
                path.move(to: p(0.62, 0.54)); path.addLine(to: p(0.72, 0.54))
                path.addLine(to: p(0.66, 0.88))
                path.addQuadCurve(to: p(0.61, 0.92), control: p(0.65, 0.92))
                path.addLine(to: p(0.54, 0.92)); path.closeSubpath()
            }, shade)
            fill(custom { path in
                path.move(to: p(0.22, 0.54))
                path.addQuadCurve(to: p(0.32, 0.34), control: p(0.17, 0.38))
                path.addQuadCurve(to: p(0.46, 0.22), control: p(0.30, 0.20))
                path.addQuadCurve(to: p(0.62, 0.20), control: p(0.52, 0.10))
                path.addQuadCurve(to: p(0.74, 0.34), control: p(0.62, 0.20))
                path.addQuadCurve(to: p(0.78, 0.54), control: p(0.87, 0.41))
                path.closeSubpath()
            }, colors.primary)
            fill(ellipse(0.455, 0.045, 0.13, 0.13), colors.accent)
            overlay(rotated(ellipse(0.25, 0.34, 0.20, 0.10), -32, 0.35, 0.39), gloss.opacity(0.34))
            overlay(rotated(ellipse(0.56, 0.26, 0.12, 0.06), -18, 0.62, 0.29), gloss.opacity(0.24))
            overlay(ellipse(0.47, 0.06, 0.04, 0.04), gloss.opacity(0.55))
        }
    }
}
