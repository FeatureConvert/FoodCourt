import SwiftUI

/// Shared by every icon below: the SVG asset pack's 0...100 viewBox, mapped once per icon
/// into whatever rect the Canvas actually has.
private func unitMap(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
    { x, y in CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
}

struct CoinIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                       width: w * rect.width, height: h * rect.height)
            }
            let line = max(1, rect.width * 0.04)
            let outline = Color(hex: "#2B1D14")

            context.fill(Path(ellipseIn: r(0.07, 0.07, 0.86, 0.86)), with: .color(Theme.coinDeep))
            let inner = Path(ellipseIn: r(0.17, 0.17, 0.66, 0.66))
            context.fill(inner, with: .color(Theme.coin))
            context.stroke(inner, with: .color(outline.opacity(0.9)), lineWidth: line * 0.7)
            context.stroke(Path(ellipseIn: r(0.07, 0.07, 0.86, 0.86)), with: .color(outline), lineWidth: line)

            var crescent = Path()
            crescent.move(to: p(0.18, 0.58))
            crescent.addQuadCurve(to: p(0.50, 0.84), control: p(0.26, 0.84))
            crescent.addQuadCurve(to: p(0.82, 0.58), control: p(0.74, 0.84))
            crescent.addQuadCurve(to: p(0.50, 0.86), control: p(0.80, 0.86))
            crescent.addQuadCurve(to: p(0.18, 0.58), control: p(0.20, 0.86))
            crescent.closeSubpath()
            context.fill(crescent, with: .color(outline.opacity(0.18)))

            var arc = Path()
            arc.move(to: p(0.32, 0.34))
            arc.addQuadCurve(to: p(0.56, 0.26), control: p(0.42, 0.24))
            context.stroke(arc, with: .color(.white.opacity(0.4)), lineWidth: line * 1.1)
        }
        .accessibilityHidden(true)
    }
}

struct GemIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.034)
            let outline = Color(hex: "#2B1D14")

            var body = Path()
            body.move(to: p(0.28, 0.20)); body.addLine(to: p(0.72, 0.20))
            body.addLine(to: p(0.88, 0.42)); body.addLine(to: p(0.50, 0.88))
            body.addLine(to: p(0.12, 0.42)); body.closeSubpath()
            context.fill(body, with: .color(Theme.gem))

            var lower = Path()
            lower.move(to: p(0.12, 0.42)); lower.addLine(to: p(0.88, 0.42))
            lower.addLine(to: p(0.50, 0.88)); lower.closeSubpath()
            context.fill(lower, with: .color(Theme.gemDeep))

            var leftFacet = Path()
            leftFacet.move(to: p(0.28, 0.20)); leftFacet.addLine(to: p(0.38, 0.42))
            leftFacet.addLine(to: p(0.12, 0.42)); leftFacet.closeSubpath()
            context.fill(leftFacet, with: .color(.white.opacity(0.2)))

            var topFacet = Path()
            topFacet.move(to: p(0.28, 0.20)); topFacet.addLine(to: p(0.72, 0.20))
            topFacet.addLine(to: p(0.62, 0.42)); topFacet.addLine(to: p(0.38, 0.42))
            topFacet.closeSubpath()
            context.fill(topFacet, with: .color(.white.opacity(0.3)))

            context.stroke(body, with: .color(outline), lineWidth: line)
            var inner = Path()
            inner.move(to: p(0.12, 0.42)); inner.addLine(to: p(0.88, 0.42))
            context.stroke(inner, with: .color(outline), lineWidth: line * 0.85)
            var facetLines = Path()
            facetLines.move(to: p(0.28, 0.20)); facetLines.addLine(to: p(0.38, 0.42))
            facetLines.addLine(to: p(0.50, 0.88))
            context.stroke(facetLines, with: .color(outline), lineWidth: line * 0.85)
            var right = Path()
            right.move(to: p(0.72, 0.20)); right.addLine(to: p(0.62, 0.42))
            context.stroke(right, with: .color(outline), lineWidth: line * 0.85)

            var gloss = Path()
            gloss.move(to: p(0.33, 0.25)); gloss.addLine(to: p(0.45, 0.25))
            gloss.addLine(to: p(0.40, 0.38)); gloss.addLine(to: p(0.30, 0.38))
            gloss.closeSubpath()
            context.fill(gloss, with: .color(.white.opacity(0.45)))
        }
        .accessibilityHidden(true)
    }
}

struct StarIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.04)
            let outline = Color(hex: "#2B1D14")

            let points: [(CGFloat, CGFloat)] = [
                (0.50, 0.10), (0.60, 0.363), (0.88, 0.376), (0.662, 0.553), (0.735, 0.824),
                (0.50, 0.67), (0.265, 0.824), (0.338, 0.553), (0.12, 0.376), (0.40, 0.363),
            ]
            var star = Path()
            star.move(to: p(points[0].0, points[0].1))
            for point in points.dropFirst() { star.addLine(to: p(point.0, point.1)) }
            star.closeSubpath()
            context.fill(star, with: .color(Theme.star))
            context.stroke(star, with: .color(outline), lineWidth: line)

            var notch = Path()
            notch.move(to: p(0.265, 0.824)); notch.addLine(to: p(0.50, 0.67))
            notch.addLine(to: p(0.735, 0.824)); notch.addLine(to: p(0.662, 0.553))
            notch.addLine(to: p(0.50, 0.67)); notch.addLine(to: p(0.338, 0.553))
            notch.closeSubpath()
            context.fill(notch, with: .color(outline.opacity(0.16)))

            var gloss = Path()
            gloss.move(to: p(0.50, 0.18)); gloss.addLine(to: p(0.56, 0.34))
            gloss.addLine(to: p(0.48, 0.44)); gloss.addLine(to: p(0.44, 0.34))
            gloss.closeSubpath()
            context.fill(gloss, with: .color(.white.opacity(0.4)))
        }
        .accessibilityHidden(true)
    }
}

struct TicketIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let raw = unitMap(rect)
            let angle = -7.0 * .pi / 180
            let pivot = raw(0.5, 0.5)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let pt = raw(x, y)
                let dx = pt.x - pivot.x, dy = pt.y - pivot.y
                return CGPoint(x: pivot.x + dx * cos(angle) - dy * sin(angle),
                               y: pivot.y + dx * sin(angle) + dy * cos(angle))
            }
            /// A rect authored in the ticket's own unrotated space, then rotated to match.
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                let corner = CGRect(x: raw(x, y).x, y: raw(x, y).y,
                                    width: w * rect.width, height: h * rect.height)
                let path = Path(roundedRect: corner, cornerRadius: radius * rect.width)
                let t = CGAffineTransform(translationX: pivot.x, y: pivot.y)
                    .rotated(by: angle)
                    .translatedBy(x: -pivot.x, y: -pivot.y)
                return path.applying(t)
            }
            let line = max(1, rect.width * 0.036)
            let outline = Color(hex: "#2B1D14")

            var body = Path()
            body.move(to: p(0.12, 0.28)); body.addLine(to: p(0.88, 0.28))
            body.addLine(to: p(0.88, 0.42))
            body.addQuadCurve(to: p(0.80, 0.50), control: p(0.80, 0.42))
            body.addQuadCurve(to: p(0.88, 0.58), control: p(0.80, 0.58))
            body.addLine(to: p(0.88, 0.72)); body.addLine(to: p(0.12, 0.72))
            body.addLine(to: p(0.12, 0.58))
            body.addQuadCurve(to: p(0.20, 0.50), control: p(0.20, 0.58))
            body.addQuadCurve(to: p(0.12, 0.42), control: p(0.20, 0.42))
            body.closeSubpath()
            context.fill(body, with: .color(Theme.coin))
            context.stroke(body, with: .color(outline), lineWidth: line)

            var perf = Path()
            perf.move(to: p(0.74, 0.30)); perf.addLine(to: p(0.74, 0.70))
            context.stroke(perf, with: .color(outline), style: StrokeStyle(lineWidth: line * 0.7, dash: [rect.width * 0.04, rect.width * 0.05]))

            context.fill(rr(0.26, 0.38, 0.34, 0.07, 0.035), with: .color(outline.opacity(0.22)))
            context.fill(rr(0.26, 0.52, 0.22, 0.07, 0.035), with: .color(outline.opacity(0.22)))

            var left = Path()
            left.move(to: p(0.12, 0.28)); left.addLine(to: p(0.26, 0.28))
            left.addLine(to: p(0.22, 0.72)); left.addLine(to: p(0.12, 0.72))
            left.addLine(to: p(0.12, 0.58))
            left.addQuadCurve(to: p(0.20, 0.50), control: p(0.20, 0.58))
            left.addQuadCurve(to: p(0.12, 0.42), control: p(0.20, 0.42))
            left.closeSubpath()
            context.fill(left, with: .color(.white.opacity(0.26)))

            context.fill(Path(ellipseIn: CGRect(x: p(0.82, 0.50).x - rect.width * 0.04,
                                                y: p(0.82, 0.50).y - rect.width * 0.04,
                                                width: rect.width * 0.08, height: rect.width * 0.08)),
                        with: .color(Theme.coinDeep))
        }
        .accessibilityHidden(true)
    }
}

struct TrophyIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.036)
            let outline = Color(hex: "#2B1D14")

            func handle(_ mirrored: Bool) -> Path {
                var path = Path()
                if mirrored {
                    path.move(to: p(0.70, 0.20))
                    path.addQuadCurve(to: p(0.70, 0.50), control: p(0.88, 0.20))
                    path.addQuadCurve(to: p(0.70, 0.42), control: p(0.88, 0.48))
                    path.addLine(to: p(0.70, 0.42))
                } else {
                    path.move(to: p(0.30, 0.20))
                    path.addQuadCurve(to: p(0.30, 0.50), control: p(0.12, 0.20))
                    path.addQuadCurve(to: p(0.30, 0.42), control: p(0.12, 0.48))
                    path.addLine(to: p(0.30, 0.42))
                }
                path.closeSubpath()
                return path
            }
            context.fill(handle(false), with: .color(Theme.coinDeep))
            context.stroke(handle(false), with: .color(outline), lineWidth: line * 0.8)
            context.fill(handle(true), with: .color(Theme.coinDeep))
            context.stroke(handle(true), with: .color(outline), lineWidth: line * 0.8)

            var cup = Path()
            cup.move(to: p(0.28, 0.16)); cup.addLine(to: p(0.72, 0.16))
            cup.addLine(to: p(0.72, 0.40))
            cup.addQuadCurve(to: p(0.50, 0.60), control: p(0.72, 0.60))
            cup.addQuadCurve(to: p(0.28, 0.40), control: p(0.28, 0.60))
            cup.closeSubpath()
            context.fill(cup, with: .color(Theme.coin))
            context.stroke(cup, with: .color(outline), lineWidth: line)

            var shade = Path()
            shade.move(to: p(0.58, 0.18)); shade.addLine(to: p(0.72, 0.18))
            shade.addLine(to: p(0.72, 0.40))
            shade.addQuadCurve(to: p(0.50, 0.60), control: p(0.72, 0.60))
            shade.addQuadCurve(to: p(0.62, 0.38), control: p(0.62, 0.54))
            shade.closeSubpath()
            context.fill(shade, with: .color(outline.opacity(0.16)))

            let stem = Path(CGRect(x: p(0.43, 0.58).x, y: p(0.43, 0.58).y,
                                   width: 0.14 * rect.width, height: 0.14 * rect.height))
            context.fill(stem, with: .color(Theme.coinDeep))
            context.stroke(stem, with: .color(outline), lineWidth: line * 0.8)

            var base = Path()
            base.move(to: p(0.30, 0.70)); base.addLine(to: p(0.70, 0.70))
            base.addQuadCurve(to: p(0.75, 0.76), control: p(0.75, 0.70))
            base.addLine(to: p(0.75, 0.84)); base.addLine(to: p(0.25, 0.84))
            base.addLine(to: p(0.25, 0.76))
            base.addQuadCurve(to: p(0.30, 0.70), control: p(0.25, 0.70))
            base.closeSubpath()
            context.fill(base, with: .color(Theme.coinDeep))
            context.stroke(base, with: .color(outline), lineWidth: line)

            var gloss = Path()
            gloss.move(to: p(0.36, 0.22)); gloss.addLine(to: p(0.45, 0.22))
            gloss.addLine(to: p(0.40, 0.52))
            gloss.addQuadCurve(to: p(0.34, 0.36), control: p(0.34, 0.46))
            gloss.closeSubpath()
            context.fill(gloss, with: .color(.white.opacity(0.32)))
        }
        .accessibilityHidden(true)
    }
}

struct CrownIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.036)
            let outline = Color(hex: "#2B1D14")

            var body = Path()
            body.move(to: p(0.14, 0.66)); body.addLine(to: p(0.14, 0.32))
            body.addLine(to: p(0.31, 0.48)); body.addLine(to: p(0.50, 0.20))
            body.addLine(to: p(0.69, 0.48)); body.addLine(to: p(0.86, 0.32))
            body.addLine(to: p(0.86, 0.66)); body.closeSubpath()
            context.fill(body, with: .color(Theme.coin))
            context.stroke(body, with: .color(outline), lineWidth: line)

            var shade = Path()
            shade.move(to: p(0.62, 0.40)); shade.addLine(to: p(0.69, 0.48))
            shade.addLine(to: p(0.86, 0.32)); shade.addLine(to: p(0.86, 0.66))
            shade.addLine(to: p(0.62, 0.66)); shade.closeSubpath()
            context.fill(shade, with: .color(outline.opacity(0.15)))

            let band = Path(roundedRect: CGRect(x: p(0.12, 0.64).x, y: p(0.12, 0.64).y,
                                                width: 0.76 * rect.width, height: 0.14 * rect.height),
                            cornerRadius: 0.05 * rect.width)
            context.fill(band, with: .color(Theme.coinDeep))
            context.stroke(band, with: .color(outline), lineWidth: line)

            var gloss = Path()
            gloss.move(to: p(0.28, 0.44)); gloss.addLine(to: p(0.32, 0.56))
            gloss.addLine(to: p(0.26, 0.62)); gloss.addLine(to: p(0.22, 0.46))
            gloss.closeSubpath()
            context.fill(gloss, with: .color(.white.opacity(0.3)))

            let r1 = 0.038 * rect.width
            context.fill(Path(ellipseIn: CGRect(x: p(0.19, 0.45).x - r1, y: p(0.19, 0.45).y - r1, width: r1 * 2, height: r1 * 2)),
                        with: .color(Theme.gem))
            let r2 = 0.05 * rect.width
            context.fill(Path(ellipseIn: CGRect(x: p(0.50, 0.31).x - r2, y: p(0.50, 0.31).y - r2, width: r2 * 2, height: r2 * 2)),
                        with: .color(Theme.negative))
            context.fill(Path(ellipseIn: CGRect(x: p(0.81, 0.45).x - r1, y: p(0.81, 0.45).y - r1, width: r1 * 2, height: r1 * 2)),
                        with: .color(Color(hex: "#B07BE8")))
        }
        .accessibilityHidden(true)
    }
}
