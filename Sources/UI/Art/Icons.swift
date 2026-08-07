import SwiftUI

struct CoinIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.04, dy: size.height * 0.04)
            context.fill(Path(ellipseIn: rect), with: .color(Theme.coinDeep))
            context.fill(Path(ellipseIn: rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)),
                         with: .color(Theme.coin))
            let inner = rect.insetBy(dx: rect.width * 0.26, dy: rect.height * 0.26)
            context.stroke(Path(ellipseIn: inner), with: .color(Theme.coinDeep.opacity(0.9)),
                           lineWidth: max(1, rect.width * 0.07))
        }
        .accessibilityHidden(true)
    }
}

struct GemIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.06, dy: size.height * 0.06)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            var body = Path()
            body.move(to: p(0.5, 0.02))
            body.addLine(to: p(0.96, 0.36))
            body.addLine(to: p(0.5, 0.98))
            body.addLine(to: p(0.04, 0.36))
            body.closeSubpath()
            context.fill(body, with: .color(Theme.gemDeep))

            var facet = Path()
            facet.move(to: p(0.5, 0.02))
            facet.addLine(to: p(0.5, 0.98))
            facet.addLine(to: p(0.04, 0.36))
            facet.closeSubpath()
            context.fill(facet, with: .color(Theme.gem))

            var top = Path()
            top.move(to: p(0.5, 0.02))
            top.addLine(to: p(0.96, 0.36))
            top.addLine(to: p(0.04, 0.36))
            top.closeSubpath()
            context.fill(top, with: .color(.white.opacity(0.28)))

            // Outline last so the silhouette stays a gem on bright fills - without it the
            // pale top facet reads as an arrow against the cyan affordability pills.
            context.stroke(body, with: .color(.black.opacity(0.35)),
                           lineWidth: max(1, rect.width * 0.06))
        }
        .accessibilityHidden(true)
    }
}

struct StarIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let outer = min(rect.width, rect.height) * 0.48
            let inner = outer * 0.46
            var path = Path()
            for index in 0..<10 {
                let radius = index.isMultiple(of: 2) ? outer : inner
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let point = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            context.fill(path, with: .color(Theme.star))
            context.stroke(path, with: .color(Theme.coinDeep), lineWidth: max(1, rect.width * 0.06))
        }
        .accessibilityHidden(true)
    }
}
