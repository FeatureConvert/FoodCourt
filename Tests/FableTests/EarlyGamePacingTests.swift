import XCTest
@testable import Fable

/// Regression net for the opening half hour. A live report showed a fresh install banking
/// the Sushi Bar (800K coins) in under five real minutes - the golden-customer/order coin
/// floors and quest floors were tuned for a mid-game board and utterly dwarf a fresh one.
/// This suite plays a hyperactive fresh install headlessly against the real engine and
/// pins the pacing so no future floor or multiplier quietly reopens the hole.
final class EarlyGamePacingTests: XCTestCase {

    struct SimResult {
        var coins: Double = 0
        var lifetime: Double = 0
        var goldenIncome: Double = 0
        var goldensCollected = 0
        var questIncome: Double = 0
        var passiveIncome: Double = 0  // includes station-order bonuses (paid inside advance)
        var sushiAffordableAt: TimeInterval? = nil
        /// Earliest finish time for the smarter strategy: build the board up to some
        /// minute, then hoard every coin at the then-current income rate until the venue
        /// is affordable. The minimum over all switch points of "now + remaining/rate".
        var bestHoardUnlockAt: TimeInterval = .infinity
        var weeklyFraction: Double = 0
        var gems = 0
        /// (elapsed, coins on hand, live income rate) each step - lets one sim run answer
        /// "when could the player bank cost C" for any candidate C after the fact.
        var trajectory: [(t: TimeInterval, coins: Double, rate: Double)] = []

        /// Earliest build-then-hoard finish time for an arbitrary price.
        func hoardTime(for cost: Double) -> TimeInterval {
            trajectory.reduce(.infinity) { best, p in
                Swift.min(best, p.t + Swift.max(0, cost - p.coins) / Swift.max(p.rate, 0.1))
            }
        }
    }

    /// Plays a fresh install the way a determined player would: the free tutorial manager
    /// on station 0, ~6 taps a second keeping the combo maxed, MAX-buying every station
    /// whenever affordable, catching every golden customer instantly, and claiming every
    /// quest the moment it completes. The queue is emulated at the UI's real 0.35s
    /// rotation throttle.
    @MainActor
    private func simulateFreshInstall(minutes: Double) -> SimResult {
        let engine = GameEngine(state: GameState.newGame(),
                                startTimers: false,
                                persistence: EphemeralPersistence())
        engine.buyQuantity = .max
        var result = SimResult()
        let dt: TimeInterval = 0.35
        var lastServed = 0
        var elapsed: TimeInterval = 0

        _ = engine.tap(station: 0)
        _ = engine.hireManager(for: 0, free: true)
        // A real player finishes or skips the tutorial in the first minute, which is what
        // arms the weekly challenge (RootView rolls it on graduation).
        engine.skipTutorial()
        engine.rollWeeklyQuestIfNeeded()

        while elapsed < minutes * 60 {
            elapsed += dt

            // Move the game clock in step so cooldowns and combo expiry see real minutes.
            engine.debugAdvanceClock(seconds: dt)
            let beforeAdvance = engine.state.coins
            engine.advance(by: dt)
            result.passiveIncome += engine.state.coins - beforeAdvance

            // Hyperactive tapping: two taps per 0.35s step ~= 6 taps/s, combo pinned at max.
            _ = engine.tap(station: 0)
            _ = engine.tap(station: 1)

            // The customer queue rotates once per serve, throttled to 0.35s - our step.
            if engine.servedCustomers > lastServed {
                lastServed = engine.servedCustomers
                engine.rollGoldenCustomer()
                engine.rollStationOrder()
            }
            if engine.golden != nil {
                let before = engine.state.coins
                _ = engine.collectGolden()
                result.goldenIncome += engine.state.coins - before
                result.goldensCollected += 1
            }

            let beforeClaims = engine.state.coins
            _ = engine.claimAllReady()
            result.questIncome += engine.state.coins - beforeClaims

            for station in 0..<6 { _ = engine.buy(station: station) }

            let cost = engine.unlockCost(for: Balance.venue(1))
            if result.sushiAffordableAt == nil, engine.state.coins >= cost {
                result.sushiAffordableAt = elapsed
            }
            let rate = Swift.max(engine.incomePerSecond, 0.1)
            let hoardFinish = elapsed + Swift.max(0, cost - engine.state.coins) / rate
            result.bestHoardUnlockAt = Swift.min(result.bestHoardUnlockAt, hoardFinish)
            result.trajectory.append((elapsed, engine.state.coins, rate))
        }

        result.coins = engine.state.coins
        result.lifetime = engine.state.lifetimeEarnings
        result.weeklyFraction = engine.state.weeklyQuest?.fraction ?? 0
        result.gems = engine.state.gems
        return result
    }

    /// The headline: even a player mashing optimally from second one should not be able to
    /// bank the second venue inside 20 minutes (the design floor) - the live report of
    /// "under 5 minutes" was the bug, and a normally-active player should land well past
    /// the frame-perfect bound this pins.
    @MainActor
    func testHyperactiveFreshInstallCannotRushTheSushiBar() {
        let result = simulateFreshInstall(minutes: 30)
        print("""
        [EarlyGamePacing] 30min hyperactive sim:
          coins on hand      \(Format.currency(result.coins))
          lifetime earned    \(Format.currency(result.lifetime))
          passive+orders     \(Format.currency(result.passiveIncome))
          goldens            \(Format.currency(result.goldenIncome)) across \(result.goldensCollected)
          quest claims       \(Format.currency(result.questIncome))
          gems               \(result.gems)
          sushi affordable   \(result.sushiAffordableAt.map { Format.duration($0) } ?? "never")
          best hoard unlock  \(Format.duration(result.bestHoardUnlockAt))
          weekly fraction    \(Int(result.weeklyFraction * 100))%
        """)
        XCTAssertNil(result.sushiAffordableAt,
                     "a fresh install banked the Sushi Bar in \(Int((result.sushiAffordableAt ?? 0) / 60)) minutes")
        XCTAssertGreaterThan(result.bestHoardUnlockAt, 20 * 60,
                             "even the optimal build-then-hoard line should not open venue 2 inside 20 minutes")
        // Candidate table for retuning the 8_000x unlock multiplier (base cost 100).
        for mult in [8_000.0, 12_000, 16_000, 24_000, 32_000, 48_000, 64_000] {
            print("  mult \(Int(mult)) -> hoard unlock \(Format.duration(result.hoardTime(for: 100 * mult)))")
        }
    }

    /// The weekly quest should not be meaningfully complete within the first minutes of a
    /// fresh install - a live report showed ~15% done before the player even found the tab.
    @MainActor
    func testWeeklyQuestIsNotMeaningfullyDoneAfterFiveMinutes() {
        let result = simulateFreshInstall(minutes: 5)
        XCTAssertLessThan(result.weeklyFraction, 0.05,
                          "weekly quest already \(Int(result.weeklyFraction * 100))% done 5 minutes into a fresh install")
    }
}
