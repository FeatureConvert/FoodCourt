import SwiftUI

/// A small four-point sparkle burst behind a coin, transcribed from `fx-coin-sparkle.svg`.
/// Used in place of a plain `CoinIcon` for the payout particle burst - it needs to read at
/// a glance even at ~14px, so it stays to three shapes.
struct CoinSparkleView: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let outline = Color(hex: "#2B1D14")
            let unit = min(rect.width, rect.height) / 100
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
            }

            let coin = Path(ellipseIn: CGRect(x: p(44, 56).x - 30 * unit, y: p(44, 56).y - 30 * unit,
                                              width: 60 * unit, height: 60 * unit))
            context.fill(coin, with: .color(Theme.coin))
            context.stroke(coin, with: .color(outline), lineWidth: unit * 4)

            var star = Path()
            let points: [(CGFloat, CGFloat)] = [
                (74, 12), (80, 27), (95, 33), (80, 39), (74, 54), (68, 39), (53, 33), (68, 27),
            ]
            star.move(to: p(points[0].0, points[0].1))
            for point in points.dropFirst() { star.addLine(to: p(point.0, point.1)) }
            star.closeSubpath()
            context.fill(star, with: .color(Theme.star))
            context.stroke(star, with: .color(outline), lineWidth: unit * 4)

            let gloss = Path(ellipseIn: CGRect(x: p(33, 45).x - 9 * unit, y: p(33, 45).y - 5 * unit,
                                               width: 18 * unit, height: 10 * unit))
            context.fill(gloss, with: .color(.white.opacity(0.4)))
        }
        .accessibilityHidden(true)
    }
}

/// The payoff animation: a spray of coins plus the amount earned, floating up and fading.
/// Driven entirely by a single `progress` value so it stays cheap to render per station.
struct CoinBurstView: View {
    let amount: Double
    let seed: Int

    @State private var progress: CGFloat = 0

    private var particles: [(dx: CGFloat, dy: CGFloat, size: CGFloat, delay: CGFloat)] {
        let rng = SeededRandom(seed: seed)
        return (0..<7).map { _ in
            (
                dx: CGFloat(rng.next(120) - 60) / 2.2,
                dy: CGFloat(rng.next(30) + 40),
                size: CGFloat(rng.next(8) + 12),
                delay: CGFloat(rng.next(20)) / 100
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(Array(particles.enumerated()), id: \.offset) { _, particle in
                let local = max(0, min(1, (progress - particle.delay) / (1 - particle.delay)))
                CoinSparkleView()
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.dx * local, y: -particle.dy * local)
                    .opacity(Double(1 - local))
                    .scaleEffect(0.6 + 0.4 * local)
            }

            // The overlay this sits in is only 66pt wide (anchored over the cooker ring), so
            // a five-character payout like "+35.01K" wrapped mid-number onto a second line
            // and read as a rendering glitch. `fixedSize` lets it lay out at its natural
            // width and overhang the anchor instead of wrapping inside it.
            Text("+\(Format.currency(amount))")
                .font(Theme.numeric(17))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.coin)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                .offset(y: -46 * progress)
                .opacity(Double(1 - progress))
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
        }
    }
}

/// Wraps a station card so each payout replaces the previous burst cleanly.
struct ServeBurstOverlay: View {
    let event: ServeEvent?

    var body: some View {
        ZStack {
            if let event {
                CoinBurstView(amount: event.amount, seed: event.id.hashValue)
                    .id(event.id)
            }
        }
    }
}

/// A one-shot confetti burst for milestone perk unlocks, transcribed from
/// `fx-confetti-burst.svg`. The source asset is a single frozen frame of confetti
/// mid-explosion; its own piece positions are reused as the animation's outward
/// endpoints, following the same `onAppear`-triggered, progress-driven shape as
/// `CoinBurstView` rather than a fresh animation system.
struct ConfettiBurstView: View {
    @State private var progress: CGFloat = 0

    private struct Piece {
        let dx: CGFloat
        let dy: CGFloat
        let angle: Double
        let color: Color
        let size: CGFloat
        let isRect: Bool
    }

    private let pieces: [Piece] = [
        Piece(dx: 0.00, dy: -0.36, angle: -14, color: Theme.coin, size: 0.16, isRect: true),
        Piece(dx: 0.27, dy: -0.27, angle: 34, color: Theme.gem, size: 0.15, isRect: true),
        Piece(dx: 0.36, dy: 0.00, angle: 8, color: Theme.negative, size: 0.17, isRect: true),
        Piece(dx: 0.25, dy: 0.27, angle: -42, color: Theme.positive, size: 0.15, isRect: true),
        Piece(dx: 0.00, dy: 0.36, angle: 12, color: Color(hex: "#B07BE8"), size: 0.16, isRect: true),
        Piece(dx: -0.25, dy: 0.27, angle: 42, color: Theme.star, size: 0.15, isRect: true),
        Piece(dx: -0.36, dy: 0.00, angle: -8, color: Theme.gem, size: 0.17, isRect: true),
        Piece(dx: -0.27, dy: -0.27, angle: -34, color: Theme.negative, size: 0.15, isRect: true),
        Piece(dx: 0.00, dy: 0.00, angle: 0, color: Theme.star, size: 0.10, isRect: false),
        Piece(dx: -0.16, dy: -0.12, angle: 0, color: Theme.positive, size: 0.06, isRect: false),
        Piece(dx: 0.16, dy: 0.12, angle: 0, color: Theme.coin, size: 0.06, isRect: false),
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    Group {
                        if piece.isRect {
                            RoundedRectangle(cornerRadius: piece.size * scale * 0.3)
                                .fill(piece.color)
                                .frame(width: piece.size * scale, height: piece.size * scale * 0.65)
                                .rotationEffect(.degrees(piece.angle))
                        } else {
                            Circle().fill(piece.color)
                                .frame(width: piece.size * scale, height: piece.size * scale)
                        }
                    }
                    .offset(x: piece.dx * scale * progress, y: piece.dy * scale * progress)
                    .opacity(Double(1 - progress))
                    .scaleEffect(0.5 + 0.5 * progress)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { progress = 1 }
        }
    }
}
