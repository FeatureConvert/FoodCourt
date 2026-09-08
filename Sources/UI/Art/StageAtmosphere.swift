import SwiftUI

/// Atmosphere for the venue stage: steam off the line, and motes hanging in the overhead light.
///
/// **Why this is a `Canvas` and not SpriteKit.** The obvious tool for particles is
/// `SKEmitterNode`, and the first version of this file used one. It was the wrong call twice
/// over. `SpriteView`'s backing stays opaque whatever you do to it - `.allowsTransparency` in
/// its options, `isOpaque` and `backgroundColor` on the `SKView`, `backgroundColor` on the
/// `SKScene` - so it painted a grey card over the room it was supposed to be floating in.
/// And the budget never justified an engine anyway: this stage is ~374x168pt carrying about
/// two dozen particles, while a single queued customer already redraws roughly forty filled
/// and stroked paths. Next to the figures standing in front of it, this layer is rounding error.
///
/// **No state, no allocation.** Every particle is a pure function of `(index, time)` - the same
/// trick the idle bob uses. There is no array to mutate, nothing to spawn or reap, and no
/// per-frame allocation; a particle "respawns" simply because its progress wraps past 1. That
/// also makes the layer resolution-independent and correct immediately after a resize, which
/// the emitter version needed an explicit rebuild to handle.
struct StageAtmosphere: View {
    /// The venue's accent - the same colour the stage already washes its light pool with, so
    /// the motes read as that light having something to catch rather than as a separate effect.
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Deliberately small. Steam reads as steam because a few wisps drift at different rates,
    /// not because there are many of them - past about a dozen it stops looking like a kitchen
    /// and starts looking like weather.
    private let steamCount = 9
    private let moteCount = 14

    var body: some View {
        // Reduce-motion drops the layer entirely rather than freezing it. A parked wisp of
        // steam hanging over the counter is worse than no steam, and this way the timeline is
        // never created at all.
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    drawSteam(in: context, size: size, t: t)
                    drawMotes(in: context, size: size, t: t)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: particles

    /// Steam off the line: rises from behind the counter lip, widens and leans as it goes, and
    /// is gone well before it reaches the sign.
    private func drawSteam(in context: GraphicsContext, size: CGSize, t: TimeInterval) {
        let life = 5.2
        for i in 0..<steamCount {
            let u = progress(i, t: t, life: life, salt: 17)
            // Sine envelope - zero at birth and death, fullest in between. A linear fade would
            // pop each wisp into existence at full width right on the counter edge.
            let fade = sin(.pi * u)
            guard fade > 0.01 else { continue }

            // Spread along the counter, clear of the outer margins where the boost buttons sit.
            let x0 = (0.12 + 0.76 * rand(i, salt: 3)) * size.width
            let lean = (rand(i, salt: 5) - 0.5) * size.width * 0.10

            let center = CGPoint(x: x0 + lean * u,
                                 y: size.height * (0.82 - 0.62 * u))
            let radius = size.height * (0.045 + 0.075 * u) * (0.75 + 0.5 * rand(i, salt: 7))
            let alpha = 0.13 * fade

            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                // A soft shoulder then a fast tail reads as a diffuse puff; a linear ramp
                // reads as a hard ball with a blurry rim.
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(alpha), location: 0),
                        .init(color: .white.opacity(alpha * 0.72), location: 0.42),
                        .init(color: .white.opacity(alpha * 0.18), location: 0.75),
                        .init(color: .white.opacity(0), location: 1)]),
                    center: center, startRadius: 0, endRadius: radius))
        }
    }

    /// Motes suspended in the overhead light. Almost invisible one at a time - the point is
    /// that the light pool stops reading as a flat gradient once something hangs in it.
    private func drawMotes(in context: GraphicsContext, size: CGSize, t: TimeInterval) {
        var context = context
        // Additive, so a mote brightens the wall behind it rather than sitting on it as a grey
        // dot, which is what an alpha-blended speck looks like against a dark interior.
        context.blendMode = .plusLighter

        let life = 13.0
        for i in 0..<moteCount {
            let u = progress(i, t: t, life: life, salt: 29)
            let fade = sin(.pi * u)
            guard fade > 0.01 else { continue }

            // A lazy sway over a slow settle, so they drift rather than fall.
            let sway = sin((u + rand(i, salt: 11)) * 2 * .pi) * size.width * 0.05
            let center = CGPoint(
                x: rand(i, salt: 13) * size.width + sway,
                y: size.height * (0.16 + 0.58 * rand(i, salt: 19)) + size.height * 0.10 * u)
            let radius = size.height * (0.006 + 0.007 * rand(i, salt: 23))

            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(accent.opacity(0.34 * fade)))
        }
    }

    // MARK: deterministic per-particle values

    /// Where particle `i` is through its life at time `t`, in 0..<1.
    ///
    /// The per-particle offset is what stops the set pulsing in lockstep; without it every wisp
    /// would be born on the same frame and the layer would read as a strobe.
    private func progress(_ i: Int, t: TimeInterval, life: Double, salt: Int) -> Double {
        let offset = rand(i, salt: salt) * life
        // Slight per-particle rate variation, so they also drift apart over time instead of
        // holding one fixed formation forever.
        let rate = 0.82 + 0.36 * rand(i, salt: salt &+ 1)
        return ((t * rate + offset) / life).truncatingRemainder(dividingBy: 1)
    }

    /// A stable 0..1 value for particle `i` on axis `salt`. A cheap integer hash rather than a
    /// seeded RNG: this runs every frame and has to give the same answer every time, or the
    /// particles would jitter between frames instead of moving.
    private func rand(_ i: Int, salt: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: (i &* 73_856_093) ^ (salt &* 19_349_663))
        h ^= h >> 33
        h = h &* 0xFF51_AFD7_ED55_8CCD
        h ^= h >> 33
        return Double(h % 100_000) / 100_000
    }
}
