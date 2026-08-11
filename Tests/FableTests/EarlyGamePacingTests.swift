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
    /// whenever affordable, catching every golden customer instantly, claiming every quest
    /// the moment it completes, AND redeeming the free Coffee Break boost (x2, no gem cost)
    /// the instant it's off cooldown - a live report showed the Sushi Bar unlocking in 8
    /// real minutes despite this suite's floor, and the gap was exactly this: the free
    /// boost stacks with combo and Happy Hour, and an earlier version of this sim never
    /// touched it, so its "worst case" wasn't. The queue is emulated at the UI's real
    /// 0.35s rotation throttle.
    @MainActor
    private func simulateFreshInstall(minutes: Double) -> SimResult {
        // Pinned INTO Happy Hour (6-8pm, x1.5 on every payout): plenty of first sessions
        // happen in the evening, so the pacing floor has to hold there, not just at noon.
        var state = GameState.newGame()
        pinClock(&state, hour: 18, minute: 5)
        let engine = GameEngine(state: state,
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

            // Both free (no gem cost, no wait beyond the fresh-save lockout), no reason a
            // determined player skips either - Rush Hour especially: x5 for 60s, stacking
            // with combo/Coffee Break/Happy Hour, was missing from every earlier version of
            // this sim and was the gap a live report caught (a save reaching the Sushi Bar
            // fast again after the combo-cap fix already landed).
            if engine.boostReady { _ = engine.claimFreeBoost() }
            if engine.rushReady { _ = engine.startRush() }

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
            // engine.incomePerSecond includes activeBoostMultiplier (Coffee Break/Rush
            // Hour) as an INSTANTANEOUS multiplier - fine for the live simulation (where
            // it's applied for exactly as many ticks as the boost is really active), but
            // wrong to extrapolate forward as a "then hoard at this rate" constant: Rush
            // Hour is a one-time 60s/30min-cooldown event, not a sustained rate, and
            // extrapolating its brief x5 forever previously made a single lucky tick look
            // like it could hoard-unlock the venue in under 6 minutes. Combo and Happy Hour
            // ARE sustainable by a still-engaged player (free, always available / time-of-
            // day), so only the boost multiplier is excluded from the hoarding rate - the
            // lump sum a real Rush Hour actually earned is still bumping `coins` above,
            // exactly like it would for a real player.
            let sustainableRate = Swift.max(
                engine.state.automatedRate * engine.comboMultiplier
                    * (engine.state.isHappyHour() ? ActivePlay.happyHourMultiplier : 1),
                0.1)
            let hoardFinish = elapsed + Swift.max(0, cost - engine.state.coins) / sustainableRate
            result.bestHoardUnlockAt = Swift.min(result.bestHoardUnlockAt, hoardFinish)
            result.trajectory.append((elapsed, engine.state.coins, sustainableRate))
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

        // Balance-pass due diligence: today's manager-cost curve (baseCost^0.72, was a flat
        // baseCost*500) made every Burger Shack manager past the first up to ~19x cheaper.
        // Reusing this sim's own trajectory (no new sim needed) to check that didn't swing
        // the pendulum the other way - full automation of venue 0 trivially early.
        print("  -- fully staffing Burger Shack (today's manager-cost curve) --")
        var venueCostSoFar = 0.0
        var cumulativeCosts: [Double] = []
        for station in Balance.venue(0).stations {
            venueCostSoFar += Balance.managerCost(spec: station)
            cumulativeCosts.append(venueCostSoFar)
            print("  through station \(station.id) (\(station.name)): cumulative \(Format.currency(venueCostSoFar)) -> \(Format.duration(result.hoardTime(for: venueCostSoFar)))")
        }
        XCTAssertLessThan(result.hoardTime(for: cumulativeCosts[3]), 30 * 60,
                          "the first four stations should stay routine early-game automation")
        XCTAssertGreaterThan(result.hoardTime(for: cumulativeCosts[5]), 2 * 3600,
                             "fully automating a whole venue should still be a real mid-game goal, not a same-session freebie")
    }

    /// The weekly quest should not be meaningfully complete within the first minutes of a
    /// fresh install - a live report showed ~15% done before the player even found the tab.
    @MainActor
    func testWeeklyQuestIsNotMeaningfullyDoneAfterFiveMinutes() {
        let result = simulateFreshInstall(minutes: 5)
        XCTAssertLessThan(result.weeklyFraction, 0.05,
                          "weekly quest already \(Int(result.weeklyFraction * 100))% done 5 minutes into a fresh install")
    }

    // MARK: - Long-horizon multi-venue simulation

    /// Plays a fully-engaged (not just hyperactive-tapping) player across real hours: MAX-
    /// buys and staffs every station of whichever venue is current, redeems Coffee Break/
    /// Rush Hour the instant they're ready, and moves the moment a new venue is affordable
    /// (matching `unlock`'s own behavior of switching focus there). Tracks the real
    /// timestamp each venue actually opened and when lifetime earnings first cross the
    /// prestige threshold - the question this answers is holistic pacing across the whole
    /// early arc, not just the first 20 minutes.
    @MainActor
    private func simulateLongHorizon(hours: Double) -> (venueUnlockedAt: [Int: TimeInterval],
                                                         prestigeEligibleAt: TimeInterval?,
                                                         finalAutomatedRate: Double,
                                                         finalLifetime: Double,
                                                         starTrajectory: [(t: TimeInterval, pendingStars: Int)]) {
        var state = GameState.newGame()
        pinClock(&state, hour: 12) // outside Happy Hour - the steady-state case, not the spike
        let engine = GameEngine(state: state, startTimers: false, persistence: EphemeralPersistence())
        engine.buyQuantity = .max
        engine.skipTutorial()

        var venueUnlockedAt: [Int: TimeInterval] = [0: 0]
        var prestigeEligibleAt: TimeInterval?
        // Sampled only for ~10 minutes around the eligibility crossing - a live report
        // was specifically about how fast pendingStars moves right after the "you can
        // prestige now" nudge first appears, not the whole run.
        var starTrajectory: [(t: TimeInterval, pendingStars: Int)] = []
        let dt: TimeInterval = 0.35
        var lastServed = 0
        var elapsed: TimeInterval = 0

        _ = engine.tap(station: 0)
        _ = engine.hireManager(for: 0, free: true)

        while elapsed < hours * 3600 {
            elapsed += dt
            engine.debugAdvanceClock(seconds: dt)
            engine.advance(by: dt)

            if engine.boostReady { _ = engine.claimFreeBoost() }
            if engine.rushReady { _ = engine.startRush() }

            _ = engine.tap(station: 0)
            _ = engine.tap(station: 1)

            if engine.servedCustomers > lastServed {
                lastServed = engine.servedCustomers
                engine.rollGoldenCustomer()
                engine.rollStationOrder()
            }
            if engine.golden != nil { _ = engine.collectGolden() }
            _ = engine.claimAllReady()

            let venue = Balance.venue(engine.state.currentVenue)
            for station in venue.stations {
                _ = engine.buy(station: station.id)
                if engine.state.venues[venue.id].stations[station.id].isOwned {
                    _ = engine.hireManager(for: station.id)
                }
            }

            if let next = engine.nextLockedVenue, engine.canUnlock(next) {
                if engine.unlock(next) {
                    venueUnlockedAt[next.id] = elapsed
                    print("  [calibration] venue \(next.id) opened at \(Format.duration(elapsed)): lifetimeEarnings=\(Format.currency(engine.state.lifetimeEarnings)) automatedRate=\(Format.currency(engine.state.automatedRate))/s")
                }
            }

            if prestigeEligibleAt == nil, engine.state.lifetimeEarnings >= Balance.minimumLifetimeForPrestige {
                prestigeEligibleAt = elapsed
            }
            if let eligibleAt = prestigeEligibleAt, elapsed - eligibleAt <= 600,
               Int(elapsed * 10).isMultiple(of: 100) { // every ~10s of sim time
                starTrajectory.append((elapsed, engine.pendingStars))
            }
        }

        return (venueUnlockedAt, prestigeEligibleAt, engine.state.automatedRate, engine.state.lifetimeEarnings,
               starTrajectory)
    }

    /// Robert's read after today's fixes: "the entire game needs to slow down by about
    /// half". This runs the real engine for a long, fully-engaged session and prints the
    /// actual venue-by-venue and first-prestige timeline so that call can be checked
    /// against data instead of feel alone.
    @MainActor
    func testLongHorizonPacingTimeline() {
        let (unlockedAt, prestigeAt, rate, lifetime, starTrajectory) = simulateLongHorizon(hours: 2)
        print("[LongHorizon] 2h fully-engaged session:")
        for id in 0...6 {
            if let t = unlockedAt[id] {
                print("  venue \(id) (\(Balance.venue(id).name)): opened at \(Format.duration(t))")
            } else {
                print("  venue \(id) (\(Balance.venue(id).name)): never opened in 8h")
            }
        }
        print("  first prestige-eligible at: \(prestigeAt.map(Format.duration) ?? "never in 8h")")
        print("  final automatedRate: \(Format.currency(rate))/s, lifetime earned: \(Format.currency(lifetime))")

        // Live report: pendingStars read ~50 right when the prestige nudge first appeared,
        // ~1,000 just two minutes later.
        print("  -- pendingStars in the 10 minutes after first becoming prestige-eligible --")
        for point in starTrajectory {
            print("  +\(Format.duration(point.t - (prestigeAt ?? 0))): pendingStars=\(point.pendingStars)")
        }
    }
}
