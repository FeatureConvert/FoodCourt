import XCTest
@testable import Fable

/// Calibration run for the new prestige floor (GameEngine.allVenuesAndStationsUnlocked):
/// how long a fully-engaged player actually takes to open all seven venues and own every
/// station in each, on a first run and across several repeat prestiges, and whether that
/// time trends up, down, or stays flat as the star multiplier compounds - the "prestige
/// scaling" question. Prints a full report; not intended to pin exact numbers the way
/// EarlyGamePacingTests does; this suite's own purpose is a fresh reading, not a regression
/// net (yet).
final class PrestigeScalingTests: XCTestCase {

    struct CycleResult {
        var venueUnlockedAt: [Int: TimeInterval] = [:]
        var venueFullyOwnedAt: [Int: TimeInterval] = [:] // every station in that venue owned
        var fullyBuiltAt: TimeInterval?                  // allVenuesAndStationsUnlocked true
        var earningsGateAt: TimeInterval?                 // minimumLifetimeForPrestige crossed
        var eligibleAt: TimeInterval?                     // both gates true - real canPrestige
        var starsAwarded: Int = 0
        var lifetimeStarsAfter: Int = 0
        var starMultiplierAfter: Double = 1
        var timedOut = false
    }

    /// Plays one prestige cycle from wherever the engine currently sits (a fresh save for
    /// cycle 0, or right after a prior `engine.prestige()` call) until every venue is open
    /// and every station in every venue is owned, or `maxHours` runs out. Manual tapping is
    /// spent on the frontier venue (the newest unlock, where stations start unstaffed) since
    /// that's where a real player's attention would go; every unlocked venue - frontier or
    /// not - gets a buy+hire pass each tick, since full completion needs every venue staffed,
    /// not just the newest one, and `advance(by:)` already pays out every unlocked venue's
    /// staffed stations regardless of which one is current.
    @MainActor
    private func runCycle(engine: GameEngine, maxHours: Double, startElapsed: TimeInterval) -> (result: CycleResult, endElapsed: TimeInterval) {
        var result = CycleResult()
        let dt: TimeInterval = 0.35
        // Re-scanning every venue's stations for an affordable buy/hire is the loop's real
        // cost - at dt=0.35s over hundreds of simulated hours it blew Xcode's 10-minute
        // per-test cap (and, as collateral damage, killed an unrelated test sharing the
        // run). A player doesn't re-check their board 3x/second either, so this is throttled
        // independently of the tap/advance cadence, which stays at the full 0.35s the other
        // pacing sims use.
        let decisionInterval: TimeInterval = 2.0
        var lastDecisionCheck: TimeInterval = -.infinity
        // advance()'s station math is delta-exact (completions = floor(elapsed/cycle)), so a
        // single advance(by: 3.0) produces the identical result to 8-9 calls of
        // advance(by: 0.35) - it just does it once instead of 8-9 times. Its per-call cost is
        // O(unlocked venues x their stations), independent of delta size, and once the board
        // fills in (managers 0->24 in profiling) that cost stopped being negligible: it was
        // the actual driver behind the growing per-hour wall time, not a leak or an unbounded
        // collection (checked: quests/errands/rivals/landmarks all stayed small and bounded).
        // Batching the call is a pure throughput win with zero fidelity loss for the
        // automated-income math; only golden/order/rush expiry precision inside advance()
        // gets coarser, which doesn't matter at this test's hundred-plus-hour scale.
        let advanceBatch: TimeInterval = 3.0
        var pendingAdvance: TimeInterval = 0
        var lastServed = engine.servedCustomers
        var elapsed = startElapsed
        let deadline = startElapsed + maxHours * 3600

        if engine.state.venues[0].unlocked { result.venueUnlockedAt[0] = startElapsed }

        let profileStart = Date()
        var lastProfileMark: TimeInterval = startElapsed
        var tAdvance: TimeInterval = 0
        var tTap: TimeInterval = 0
        var tMisc: TimeInterval = 0
        var tDecision: TimeInterval = 0
        while elapsed < deadline {
            elapsed += dt
            if elapsed - lastProfileMark >= 3600 {
                lastProfileMark = elapsed
                print("[PROFILE] simHour=\(Int(elapsed / 3600)) wallSec=\(String(format: "%.1f", Date().timeIntervalSince(profileStart))) advance=\(String(format: "%.1f", tAdvance)) tap=\(String(format: "%.1f", tTap)) misc=\(String(format: "%.1f", tMisc)) decision=\(String(format: "%.1f", tDecision)) quests=\(engine.state.quests.count) errands=\(engine.state.errands.count) rivals=\(engine.state.league.rivals.count) landmarks=\(engine.state.landmarksCrossed.count) claimedAch=\(engine.state.claimedAchievements.count) venues=\(engine.state.venues.count) managers=\(engine.state.managers.count)")
            }
            engine.debugAdvanceClock(seconds: dt)
            pendingAdvance += dt
            if pendingAdvance >= advanceBatch {
                let mark = Date()
                engine.advance(by: pendingAdvance)
                pendingAdvance = 0
                tAdvance += Date().timeIntervalSince(mark)
            }

            if engine.boostReady { _ = engine.claimFreeBoost() }
            if engine.rushReady { _ = engine.startRush() }

            var mark = Date()
            let frontier = engine.state.currentVenue
            for station in Balance.venue(frontier).stations {
                _ = engine.tap(station: station.id)
            }
            tTap += Date().timeIntervalSince(mark)

            mark = Date()
            if engine.servedCustomers > lastServed {
                lastServed = engine.servedCustomers
                engine.rollGoldenCustomer()
                engine.rollStationOrder()
            }
            if engine.golden != nil { _ = engine.collectGolden() }
            tMisc += Date().timeIntervalSince(mark)

            if elapsed - lastDecisionCheck >= decisionInterval {
                mark = Date()
                lastDecisionCheck = elapsed
                _ = engine.claimAllReady()
                for venue in Balance.venues where engine.state.venues[venue.id].unlocked {
                    engine.switchTo(venue: venue.id)
                    for station in venue.stations {
                        _ = engine.buy(station: station.id)
                        if engine.state.venues[venue.id].stations[station.id].isOwned {
                            _ = engine.hireManager(for: station.id)
                        }
                    }
                    if result.venueFullyOwnedAt[venue.id] == nil,
                       engine.state.venues[venue.id].stations.allSatisfy(\.isOwned) {
                        result.venueFullyOwnedAt[venue.id] = elapsed
                    }
                }
                engine.switchTo(venue: frontier)

                if let next = engine.nextLockedVenue, engine.canUnlock(next) {
                    if engine.unlock(next) {
                        result.venueUnlockedAt[next.id] = elapsed
                    }
                }
                tDecision += Date().timeIntervalSince(mark)
            }

            if result.earningsGateAt == nil, engine.state.lifetimeEarnings >= Balance.minimumLifetimeForPrestige {
                result.earningsGateAt = elapsed
            }
            if result.fullyBuiltAt == nil, engine.allVenuesAndStationsUnlocked {
                result.fullyBuiltAt = elapsed
            }
            if result.eligibleAt == nil, engine.canPrestige {
                result.eligibleAt = elapsed
                break
            }
        }

        if result.eligibleAt == nil { result.timedOut = true }
        return (result, elapsed)
    }

    @MainActor
    func testPrestigeScalingAcrossRepeatCycles() {
        // This is a calibration run, not a regression test - it's fine for it to genuinely
        // take a while. The 10-minute default (Fable.xctestplan: testTimeoutsEnabled) is
        // right for everything else in the suite; this one test needs its own room, per
        // Apple's own guidance in the timeout error message.
        executionTimeAllowance = 3 * 3600
        var state = GameState.newGame()
        pinClock(&state, hour: 12)
        let engine = GameEngine(state: state, startTimers: false, persistence: EphemeralPersistence())
        engine.rng = SplitMix64(seed: 20_260_810)
        engine.buyQuantity = .max
        engine.skipTutorial()
        _ = engine.tap(station: 0)
        _ = engine.hireManager(for: 0, free: true)

        let cycles = 4
        // 400h blew Xcode's 10-minute per-test cap even after the decision-cadence throttle
        // above, and took an unrelated test down with it (whole runner got killed mid-suite).
        // 150h is still a generous ceiling against Balance.swift's own venue-pacing comments
        // (tens of hours, not hundreds) - a timeout here is still informative, not ambiguous.
        let maxHoursPerCycle = 150.0
        var elapsed: TimeInterval = 0
        var results: [CycleResult] = []

        for cycle in 0..<cycles {
            let (result, endElapsed) = runCycle(engine: engine, maxHours: maxHoursPerCycle, startElapsed: elapsed)
            elapsed = endElapsed
            var r = result
            if !r.timedOut {
                let award = engine.pendingStars
                _ = engine.prestige()
                r.starsAwarded = award
                r.lifetimeStarsAfter = engine.state.lifetimeStars
                r.starMultiplierAfter = Balance.starMultiplier(stars: engine.state.lifetimeStars)
            }
            results.append(r)
            let header = r.timedOut
                ? "TIMED OUT after \(Format.duration(maxHoursPerCycle * 3600))"
                : "eligible at absolute t=\(Format.duration(r.eligibleAt ?? 0))"
            print("""
            [PrestigeScaling] cycle \(cycle) \(header):
              earnings gate crossed at   \(r.earningsGateAt.map(Format.duration) ?? "never")
              full buildout at           \(r.fullyBuiltAt.map(Format.duration) ?? "never")
              real eligibility (both) at \(r.eligibleAt.map(Format.duration) ?? "never")
              stars awarded              \(r.starsAwarded)
              lifetime stars after       \(r.lifetimeStarsAfter)
              star multiplier after      x\(String(format: "%.2f", r.starMultiplierAfter))
              per-venue unlock/own timeline:
            """)
            for id in 0...6 {
                let name = Balance.venue(id).name
                let unlocked = r.venueUnlockedAt[id].map(Format.duration) ?? "never"
                let owned = r.venueFullyOwnedAt[id].map(Format.duration) ?? "never"
                print("    venue \(id) (\(name)): unlocked \(unlocked), fully owned \(owned)")
            }
            if r.timedOut {
                print("  [PrestigeScaling] stopping - cycle \(cycle) did not reach eligibility in \(maxHoursPerCycle)h simulated")
                break
            }
        }

        print("[PrestigeScaling] cycle-over-cycle eligibility duration (wall time per cycle, not cumulative):")
        var previousEnd: TimeInterval = 0
        for (i, r) in results.enumerated() {
            guard let eligibleAt = r.eligibleAt else { continue }
            print("  cycle \(i): \(Format.duration(eligibleAt - previousEnd))")
            previousEnd = eligibleAt
        }
    }
}
