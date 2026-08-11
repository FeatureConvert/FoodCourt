import XCTest
@testable import Fable

/// A long-lived save reaches numbers that a fresh one never does. `Double` handles them
/// fine; `Int` does not - and `Int(aDoubleTooLargeToFit)` is a fatal runtime trap, not a
/// throwable error, so a single unguarded conversion crashes the app on every launch once a
/// save crosses the line (exactly the failure `Balance.maxSaneLifetimeStars` was added for).
///
/// The long-horizon pacing sim crashes somewhere past ~2 simulated hours; these pin the
/// conversions on the money paths that get there first.
final class ExtremeScaleTests: XCTestCase {

    @MainActor
    private func engine(_ state: GameState) -> GameEngine {
        GameEngine(state: state, startTimers: false, persistence: EphemeralPersistence())
    }

    /// The Gauntlet purse divides the run's score by its baseline and converts to `Int`.
    /// A late-game sprint scores far past `Int.max` (9.2e18) - the division result is what
    /// gets converted, so a big enough score over a small baseline traps outright.
    @MainActor
    func testGauntletPurseSurvivesAScoreBeyondIntMax() {
        var state = GameState.newGame()
        state.gauntletEndsAt = state.now.addingTimeInterval(-1) // already expired: settles on tick
        state.gauntletScore = 1e30
        state.gauntletBaseline = 1
        let e = engine(state)

        e.advance(by: 0.35)

        XCTAssertNil(e.state.gauntletEndsAt, "the sprint settled instead of trapping")
        XCTAssertLessThanOrEqual(e.state.gems, 25 + 90, "purse still respects its 90-gem cap")
    }

    /// Same conversion, reached the other way: a modest score over a sub-1 baseline. The
    /// baseline is clamped to >= 1 so this can't divide by zero, but it confirms the clamp
    /// is actually doing that job.
    @MainActor
    func testGauntletPurseSurvivesAZeroBaseline() {
        var state = GameState.newGame()
        state.gauntletEndsAt = state.now.addingTimeInterval(-1)
        state.gauntletScore = 1e18
        state.gauntletBaseline = 0
        let e = engine(state)

        e.advance(by: 0.35)

        XCTAssertNil(e.state.gauntletEndsAt)
    }

    /// The whole tick loop at a scale a multi-hour engaged run genuinely reaches: every
    /// station maxed on the deepest venue, earnings past what `Int` can hold.
    @MainActor
    func testTickLoopSurvivesADeepLateGameBoard() {
        var state = GameState.newGame()
        for venue in state.venues.indices {
            state.venues[venue].unlocked = true
            for station in state.venues[venue].stations.indices {
                state.venues[venue].stations[station].level = 3_000
            }
        }
        state.currentVenue = Balance.venues.count - 1
        state.lifetimeEarnings = 1e25
        state.coins = 1e25
        let e = engine(state)

        for _ in 0..<20 { e.advance(by: 0.35) }

        XCTAssertTrue(e.state.coins.isFinite, "coins stayed a real number")
        XCTAssertTrue(e.state.lifetimeEarnings.isFinite)
    }
}
