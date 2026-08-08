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
    var cup: Color = Theme.coin
    var base: Color = Theme.coinDeep

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
            context.fill(handle(false), with: .color(base))
            context.stroke(handle(false), with: .color(outline), lineWidth: line * 0.8)
            context.fill(handle(true), with: .color(base))
            context.stroke(handle(true), with: .color(outline), lineWidth: line * 0.8)

            var cupPath = Path()
            cupPath.move(to: p(0.28, 0.16)); cupPath.addLine(to: p(0.72, 0.16))
            cupPath.addLine(to: p(0.72, 0.40))
            cupPath.addQuadCurve(to: p(0.50, 0.60), control: p(0.72, 0.60))
            cupPath.addQuadCurve(to: p(0.28, 0.40), control: p(0.28, 0.60))
            cupPath.closeSubpath()
            context.fill(cupPath, with: .color(cup))
            context.stroke(cupPath, with: .color(outline), lineWidth: line)

            var shade = Path()
            shade.move(to: p(0.58, 0.18)); shade.addLine(to: p(0.72, 0.18))
            shade.addLine(to: p(0.72, 0.40))
            shade.addQuadCurve(to: p(0.50, 0.60), control: p(0.72, 0.60))
            shade.addQuadCurve(to: p(0.62, 0.38), control: p(0.62, 0.54))
            shade.closeSubpath()
            context.fill(shade, with: .color(outline.opacity(0.16)))

            let stem = Path(CGRect(x: p(0.43, 0.58).x, y: p(0.43, 0.58).y,
                                   width: 0.14 * rect.width, height: 0.14 * rect.height))
            context.fill(stem, with: .color(base))
            context.stroke(stem, with: .color(outline), lineWidth: line * 0.8)

            var basePath = Path()
            basePath.move(to: p(0.30, 0.70)); basePath.addLine(to: p(0.70, 0.70))
            basePath.addQuadCurve(to: p(0.75, 0.76), control: p(0.75, 0.70))
            basePath.addLine(to: p(0.75, 0.84)); basePath.addLine(to: p(0.25, 0.84))
            basePath.addLine(to: p(0.25, 0.76))
            basePath.addQuadCurve(to: p(0.30, 0.70), control: p(0.25, 0.70))
            basePath.closeSubpath()
            context.fill(basePath, with: .color(base))
            context.stroke(basePath, with: .color(outline), lineWidth: line)

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

// MARK: - Functional glyphs
//
// A second, plainer register: single-tint-fill + fixed outline shapes standing in for the
// SF Symbols still used in dense list rows (achievements, quests, perks, shop, help). These
// intentionally skip the multi-color "real object" treatment above - at 16-20pt in a list,
// that level of detail would just be noise - and every one takes an explicit `tint` since
// their whole job is to carry the same dynamic state-color the SF Symbol they replace did
// (e.g. an achievement row dims its icon until claimed).

struct TapIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.08)
            let outline = Color(hex: "#2B1D14")
            let center = p(0.46, 0.60)

            let dot = Path(ellipseIn: CGRect(x: center.x - 0.15 * rect.width, y: center.y - 0.15 * rect.width,
                                             width: 0.30 * rect.width, height: 0.30 * rect.width))
            context.fill(dot, with: .color(tint))
            context.stroke(dot, with: .color(outline), lineWidth: line * 0.6)

            for radius: CGFloat in [0.26, 0.40] {
                var ring = Path()
                ring.addArc(center: center, radius: radius * rect.width,
                           startAngle: .degrees(-155), endAngle: .degrees(-25), clockwise: false)
                context.stroke(ring, with: .color(outline), style: .init(lineWidth: line * 0.6, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct BagIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.06)
            let outline = Color(hex: "#2B1D14")

            var bag = Path()
            bag.move(to: p(0.26, 0.36)); bag.addLine(to: p(0.74, 0.36))
            bag.addLine(to: p(0.68, 0.84)); bag.addLine(to: p(0.32, 0.84))
            bag.closeSubpath()
            context.fill(bag, with: .color(tint))
            context.stroke(bag, with: .color(outline), lineWidth: line)

            var fold = Path()
            fold.move(to: p(0.29, 0.50)); fold.addLine(to: p(0.71, 0.50))
            context.stroke(fold, with: .color(outline.opacity(0.5)), lineWidth: line * 0.6)

            var handle = Path()
            handle.move(to: p(0.40, 0.36))
            handle.addQuadCurve(to: p(0.60, 0.36), control: p(0.50, 0.14))
            context.stroke(handle, with: .color(outline), lineWidth: line * 0.7)
        }
        .accessibilityHidden(true)
    }
}

struct FlameIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.06)
            let outline = Color(hex: "#2B1D14")

            var flame = Path()
            flame.move(to: p(0.50, 0.86))
            flame.addQuadCurve(to: p(0.23, 0.56), control: p(0.20, 0.76))
            flame.addQuadCurve(to: p(0.40, 0.18), control: p(0.20, 0.36))
            flame.addQuadCurve(to: p(0.44, 0.40), control: p(0.35, 0.30))
            flame.addQuadCurve(to: p(0.62, 0.14), control: p(0.54, 0.30))
            flame.addQuadCurve(to: p(0.79, 0.56), control: p(0.78, 0.28))
            flame.addQuadCurve(to: p(0.50, 0.86), control: p(0.80, 0.78))
            flame.closeSubpath()
            context.fill(flame, with: .color(tint))
            context.stroke(flame, with: .color(outline), lineWidth: line * 0.6)
        }
        .accessibilityHidden(true)
    }
}

struct BoltIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.06)
            let outline = Color(hex: "#2B1D14")

            var bolt = Path()
            bolt.move(to: p(0.58, 0.14)); bolt.addLine(to: p(0.28, 0.56))
            bolt.addLine(to: p(0.46, 0.56)); bolt.addLine(to: p(0.40, 0.88))
            bolt.addLine(to: p(0.74, 0.42)); bolt.addLine(to: p(0.54, 0.42))
            bolt.closeSubpath()
            context.fill(bolt, with: .color(tint))
            context.stroke(bolt, with: .color(outline), lineWidth: line * 0.55)
        }
        .accessibilityHidden(true)
    }
}

struct PeopleIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.055)
            let outline = Color(hex: "#2B1D14")

            func person(headX: CGFloat, headY: CGFloat, headR: CGFloat, opacity: Double) -> (Path, Path) {
                let head = Path(ellipseIn: CGRect(x: p(headX, headY).x - headR * rect.width,
                                                  y: p(headX, headY).y - headR * rect.height,
                                                  width: headR * 2 * rect.width, height: headR * 2 * rect.height))
                var bodyPath = Path()
                bodyPath.move(to: p(headX - 0.22, 0.86))
                bodyPath.addQuadCurve(to: p(headX, headY + headR + 0.02), control: p(headX - 0.22, headY + headR + 0.10))
                bodyPath.addQuadCurve(to: p(headX + 0.22, 0.86), control: p(headX + 0.22, headY + headR + 0.10))
                bodyPath.closeSubpath()
                _ = opacity
                return (head, bodyPath)
            }

            let back = person(headX: 0.64, headY: 0.32, headR: 0.13, opacity: 0.6)
            context.fill(back.1, with: .color(tint.opacity(0.55)))
            context.fill(back.0, with: .color(tint.opacity(0.55)))
            context.stroke(back.0, with: .color(outline.opacity(0.7)), lineWidth: line * 0.6)

            let front = person(headX: 0.36, headY: 0.36, headR: 0.16, opacity: 1)
            context.fill(front.1, with: .color(tint))
            context.stroke(front.1, with: .color(outline), lineWidth: line * 0.6)
            context.fill(front.0, with: .color(tint))
            context.stroke(front.0, with: .color(outline), lineWidth: line * 0.6)
        }
        .accessibilityHidden(true)
    }
}

struct MapIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.05)
            let outline = Color(hex: "#2B1D14")

            let panel = Path(roundedRect: CGRect(x: p(0.16, 0.20).x, y: p(0.16, 0.20).y,
                                                 width: 0.68 * rect.width, height: 0.60 * rect.height),
                             cornerRadius: 0.05 * rect.width)
            context.fill(panel, with: .color(tint))
            context.stroke(panel, with: .color(outline), lineWidth: line)

            for x: CGFloat in [0.395, 0.605] {
                var fold = Path()
                fold.move(to: p(x, 0.20)); fold.addLine(to: p(x, 0.80))
                context.stroke(fold, with: .color(outline.opacity(0.5)), lineWidth: line * 0.55)
            }

            var trail = Path()
            trail.move(to: p(0.26, 0.62))
            trail.addQuadCurve(to: p(0.50, 0.42), control: p(0.38, 0.72))
            trail.addQuadCurve(to: p(0.72, 0.34), control: p(0.60, 0.30))
            context.stroke(trail, with: .color(outline),
                           style: .init(lineWidth: line * 0.55, lineCap: .round, dash: [line * 0.5, line * 0.7]))

            let pin = Path(ellipseIn: CGRect(x: p(0.72, 0.34).x - 0.05 * rect.width, y: p(0.72, 0.34).y - 0.05 * rect.width,
                                             width: 0.10 * rect.width, height: 0.10 * rect.width))
            context.fill(pin, with: .color(Theme.negative))
            context.stroke(pin, with: .color(outline), lineWidth: line * 0.4)
        }
        .accessibilityHidden(true)
    }
}

struct BookIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.055)
            let outline = Color(hex: "#2B1D14")

            let cover = Path(roundedRect: CGRect(x: p(0.20, 0.16).x, y: p(0.20, 0.16).y,
                                                 width: 0.60 * rect.width, height: 0.68 * rect.height),
                             cornerRadius: 0.05 * rect.width)
            context.fill(cover, with: .color(tint))
            context.stroke(cover, with: .color(outline), lineWidth: line)

            var spine = Path()
            spine.move(to: p(0.44, 0.16)); spine.addLine(to: p(0.44, 0.84))
            context.stroke(spine, with: .color(outline.opacity(0.6)), lineWidth: line * 0.6)

            var ribbon = Path()
            ribbon.move(to: p(0.60, 0.16)); ribbon.addLine(to: p(0.60, 0.40))
            ribbon.addLine(to: p(0.66, 0.32)); ribbon.addLine(to: p(0.72, 0.40))
            ribbon.addLine(to: p(0.72, 0.16))
            context.fill(ribbon, with: .color(Theme.negative))
            context.stroke(ribbon, with: .color(outline), lineWidth: line * 0.4)
        }
        .accessibilityHidden(true)
    }
}

struct TimerIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.07)
            let outline = Color(hex: "#2B1D14")

            let face = Path(ellipseIn: CGRect(x: p(0.18, 0.24).x, y: p(0.18, 0.24).y,
                                              width: 0.64 * rect.width, height: 0.64 * rect.height))
            context.fill(face, with: .color(tint))
            context.stroke(face, with: .color(outline), lineWidth: line)

            let center = p(0.50, 0.56)
            var hourHand = Path()
            hourHand.move(to: center); hourHand.addLine(to: p(0.50, 0.36))
            context.stroke(hourHand, with: .color(outline), style: .init(lineWidth: line * 0.7, lineCap: .round))
            var minuteHand = Path()
            minuteHand.move(to: center); minuteHand.addLine(to: p(0.64, 0.56))
            context.stroke(minuteHand, with: .color(outline), style: .init(lineWidth: line * 0.6, lineCap: .round))

            let stem = Path(roundedRect: CGRect(x: p(0.42, 0.10).x, y: p(0.42, 0.10).y,
                                                width: 0.16 * rect.width, height: 0.08 * rect.height),
                            cornerRadius: 0.02 * rect.width)
            context.fill(stem, with: .color(outline))
        }
        .accessibilityHidden(true)
    }
}

struct BellIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.055)
            let outline = Color(hex: "#2B1D14")

            var bell = Path()
            bell.move(to: p(0.30, 0.68))
            bell.addQuadCurve(to: p(0.32, 0.30), control: p(0.26, 0.50))
            bell.addQuadCurve(to: p(0.50, 0.16), control: p(0.36, 0.18))
            bell.addQuadCurve(to: p(0.68, 0.30), control: p(0.64, 0.18))
            bell.addQuadCurve(to: p(0.70, 0.68), control: p(0.74, 0.50))
            bell.addLine(to: p(0.30, 0.68))
            bell.closeSubpath()
            context.fill(bell, with: .color(tint))
            context.stroke(bell, with: .color(outline), lineWidth: line)

            let clapper = Path(ellipseIn: CGRect(x: p(0.50, 0.78).x - 0.06 * rect.width, y: p(0.50, 0.78).y - 0.06 * rect.width,
                                                 width: 0.12 * rect.width, height: 0.12 * rect.width))
            context.fill(clapper, with: .color(outline))
        }
        .accessibilityHidden(true)
    }
}

struct InfinityIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.14)
            let outline = Color(hex: "#2B1D14")

            var loop = Path()
            loop.move(to: p(0.50, 0.50))
            loop.addCurve(to: p(0.50, 0.50), control1: p(0.20, 0.20), control2: p(0.20, 0.80))
            loop.addCurve(to: p(0.50, 0.50), control1: p(0.80, 0.80), control2: p(0.80, 0.20))
            context.stroke(loop, with: .color(outline), style: .init(lineWidth: line, lineCap: .round, lineJoin: .round))
            context.stroke(loop, with: .color(tint), style: .init(lineWidth: line * 0.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct CycleIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.10)
            let outline = Color(hex: "#2B1D14")
            let radius = 0.30 * rect.width

            func arc(start: Double, end: Double) -> Path {
                var path = Path()
                path.addArc(center: p(0.50, 0.50), radius: radius, startAngle: .degrees(start),
                           endAngle: .degrees(end), clockwise: false)
                return path
            }
            let top = arc(start: -160, end: 20)
            let bottom = arc(start: 20, end: 200)
            for a in [top, bottom] {
                context.stroke(a, with: .color(outline), style: .init(lineWidth: line, lineCap: .round))
                context.stroke(a, with: .color(tint), style: .init(lineWidth: line * 0.55, lineCap: .round))
            }

            func arrowhead(at angle: Double, pointing: Double) -> Path {
                let tip = CGPoint(x: p(0.50, 0.50).x + radius * cos(angle * .pi / 180),
                                  y: p(0.50, 0.50).y + radius * sin(angle * .pi / 180))
                var head = Path()
                let size = 0.13 * rect.width
                head.move(to: CGPoint(x: tip.x + size * cos((pointing + 150) * .pi / 180),
                                      y: tip.y + size * sin((pointing + 150) * .pi / 180)))
                head.addLine(to: tip)
                head.addLine(to: CGPoint(x: tip.x + size * cos((pointing - 150) * .pi / 180),
                                         y: tip.y + size * sin((pointing - 150) * .pi / 180)))
                return head
            }
            context.stroke(arrowhead(at: 20, pointing: -70), with: .color(outline),
                           style: .init(lineWidth: line * 0.6, lineCap: .round, lineJoin: .round))
            context.stroke(arrowhead(at: 200, pointing: 110), with: .color(outline),
                           style: .init(lineWidth: line * 0.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct SnowflakeIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.07)
            let center = p(0.50, 0.50)

            for angle: Double in [0, 60, 120] {
                let rad = angle * .pi / 180
                let dx = cos(rad) * 0.34 * rect.width, dy = sin(rad) * 0.34 * rect.height
                var spoke = Path()
                spoke.move(to: CGPoint(x: center.x - dx, y: center.y - dy))
                spoke.addLine(to: CGPoint(x: center.x + dx, y: center.y + dy))
                context.stroke(spoke, with: .color(tint), style: .init(lineWidth: line, lineCap: .round))

                for sign: CGFloat in [-1, 1] {
                    let tickBase = CGPoint(x: center.x + dx * 0.62, y: center.y + dy * 0.62)
                    let perp = rad + .pi / 2
                    var tick = Path()
                    tick.move(to: tickBase)
                    tick.addLine(to: CGPoint(x: tickBase.x + sign * cos(perp) * 0.12 * rect.width,
                                             y: tickBase.y + sign * sin(perp) * 0.12 * rect.height))
                    context.stroke(tick, with: .color(tint), style: .init(lineWidth: line * 0.7, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CupIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let line = max(1, rect.width * 0.06)
            let outline = Color(hex: "#2B1D14")

            var cup = Path()
            cup.move(to: p(0.26, 0.32)); cup.addLine(to: p(0.68, 0.32))
            cup.addLine(to: p(0.62, 0.82)); cup.addLine(to: p(0.32, 0.82))
            cup.closeSubpath()
            context.fill(cup, with: .color(tint))
            context.stroke(cup, with: .color(outline), lineWidth: line)

            var handle = Path()
            handle.addArc(center: p(0.74, 0.48), radius: 0.13 * rect.width,
                         startAngle: .degrees(-70), endAngle: .degrees(90), clockwise: false)
            context.stroke(handle, with: .color(outline), lineWidth: line * 0.7)

            for x: CGFloat in [0.40, 0.52] {
                var steam = Path()
                steam.move(to: p(x, 0.24))
                steam.addQuadCurve(to: p(x, 0.10), control: p(x - 0.06, 0.17))
                context.stroke(steam, with: .color(outline.opacity(0.6)),
                               style: .init(lineWidth: line * 0.5, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct SparklesIcon: View {
    var tint: Color
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let p = unitMap(rect)
            let outline = Color(hex: "#2B1D14")

            func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                var path = Path()
                path.move(to: p(cx, cy - r))
                path.addQuadCurve(to: p(cx + r, cy), control: p(cx, cy))
                path.addQuadCurve(to: p(cx, cy + r), control: p(cx, cy))
                path.addQuadCurve(to: p(cx - r, cy), control: p(cx, cy))
                path.addQuadCurve(to: p(cx, cy - r), control: p(cx, cy))
                path.closeSubpath()
                return path
            }
            let big = star(0.56, 0.44, 0.30)
            context.fill(big, with: .color(tint))
            context.stroke(big, with: .color(outline), lineWidth: max(1, rect.width * 0.035))

            let small = star(0.24, 0.72, 0.14)
            context.fill(small, with: .color(tint))
            context.stroke(small, with: .color(outline), lineWidth: max(1, rect.width * 0.03))
        }
        .accessibilityHidden(true)
    }
}

/// Dispatches an SF Symbol name to the matching bespoke icon above, tinted like the symbol
/// it replaces would have been. Falls back to the system glyph for anything not mapped, so
/// call sites can adopt this incrementally with zero risk to symbols left unmapped.
@ViewBuilder
func GlyphIcon(_ symbol: String, tint: Color) -> some View {
    switch symbol {
    case "hand.tap.fill": TapIcon(tint: tint)
    case "takeoutbag.and.cup.and.straw.fill": BagIcon(tint: tint)
    case "flame.fill": FlameIcon(tint: tint)
    case "bolt.fill": BoltIcon(tint: tint)
    case "person.2.fill": PeopleIcon(tint: tint)
    case "map.fill": MapIcon(tint: tint)
    case "book.closed.fill": BookIcon(tint: tint)
    case "timer": TimerIcon(tint: tint)
    case "bell.fill", "bell.badge.fill": BellIcon(tint: tint)
    case "infinity": InfinityIcon(tint: tint)
    case "arrow.triangle.2.circlepath": CycleIcon(tint: tint)
    case "snowflake": SnowflakeIcon(tint: tint)
    case "cup.and.saucer.fill": CupIcon(tint: tint)
    case "sparkles": SparklesIcon(tint: tint)
    case "dollarsign.circle.fill": CoinIcon()
    case "diamond.fill": GemIcon()
    case "ticket.fill": TicketIcon()
    case "trophy.fill": TrophyIcon(cup: tint, base: tint.opacity(0.75))
    case "crown.fill": CrownIcon()
    default: Image(systemName: symbol).foregroundStyle(tint)
    }
}
