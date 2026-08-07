import SwiftUI

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
                CoinIcon()
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.dx * local, y: -particle.dy * local)
                    .opacity(Double(1 - local))
                    .scaleEffect(0.6 + 0.4 * local)
            }

            Text("+\(Format.currency(amount))")
                .font(Theme.numeric(17))
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
