import Foundation

/// The engine's source of randomness, injectable so tests can pin it.
///
/// Everything chance-driven in `GameEngine` - golden customers, the VIP critic jackpot,
/// station orders, tool drops, recipe drops, manager recruitment - used to call the global
/// `Double.random(in:)` directly. That made the pacing sims in `EarlyGamePacingTests`
/// genuinely non-deterministic: the same tuning measured anywhere from 18 to 28 minutes to
/// the Sushi Bar depending purely on how the goldens fell, so a regression assert on "not
/// before 20 minutes" was a coin flip rather than a floor, and a real regression could hide
/// inside the noise for several runs before anyone saw it fail.
///
/// Production still gets `SystemRandomNumberGenerator` - nothing about live play changes.
///
/// SplitMix64: tiny, fast, well-distributed, and (unlike the xorshift `SeededRandom` in
/// CustomerSprite.swift, which is a UI helper for stable sprite art rather than a
/// `RandomNumberGenerator`) it conforms to the standard protocol, so every existing
/// `.random(in:)` / `.randomElement()` call site works unchanged apart from `using: &rng`.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
