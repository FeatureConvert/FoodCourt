import XCTest
@testable import Fable

/// Pins `state.now` to the next occurrence of a fixed local wall-clock time, with
/// `lastSeen` moved along so the jump doesn't manufacture offline earnings. Payout math is
/// time-of-day dependent - Happy Hour (6-8pm local) multiplies every payout by x1.5, which
/// silently broke exact-value assertions whenever the suite ran in the evening.
func pinClock(_ state: inout GameState, hour: Int, minute: Int = 30) {
    let target = Calendar.current.nextDate(after: Date(),
                                           matching: DateComponents(hour: hour, minute: minute),
                                           matchingPolicy: .nextTime)!
    state.timeOffset = target.timeIntervalSince(Date())
    state.lastSeen = target
    // The pin can land up to a day ahead of the wall clock; drag the board-age anchor
    // along or the jump alone ages the board into the staleness cost tax.
    state.boardStartedAt = target
}

/// Offline earnings, the daily-login calendar, and the engine actions that move money
/// around. These are the systems where an off-by-one costs the player real progress.
final class ProgressionTests: XCTestCase {

    private func staffedState(level: Int = 10) -> GameState {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = level
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        return state
    }

    // MARK: Offline earnings

    func testOnlyStaffedStationsEarnOffline() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        XCTAssertEqual(OfflineEarnings.automatedIncomePerSecond(state), 0,
                       "an unstaffed station should not earn while the app is closed")

        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        XCTAssertGreaterThan(OfflineEarnings.automatedIncomePerSecond(state), 0)
    }

    func testLockedVenuesDoNotContribute() {
        var state = staffedState()
        // Staff a station in a venue that was never opened.
        state.venues[1].stations[0].level = 50
        state.hire(specID: ManagerCatalog.traineeID, venue: 1, station: 0)
        let locked = OfflineEarnings.automatedIncomePerSecond(state)

        state.venues[1].unlocked = true
        let unlocked = OfflineEarnings.automatedIncomePerSecond(state)
        XCTAssertGreaterThan(unlocked, locked)
    }

    func testShortAbsenceProducesNoReport() {
        var state = staffedState()
        state.lastSeen = Date()
        XCTAssertNil(OfflineEarnings.compute(state: state, now: state.lastSeen.addingTimeInterval(30)))
    }

    func testOfflineIsCappedAndDiscounted() {
        var state = staffedState()
        // Season twists rotate by id; pin one with no offline bonus (id % 4 == 0) so the
        // discount being asserted is the base one.
        state.festival.seasonID = 4
        let start = Date()
        state.lastSeen = start

        let rate = OfflineEarnings.automatedIncomePerSecond(state)
        let report = OfflineEarnings.compute(state: state, now: start.addingTimeInterval(10 * 3600))

        let expectedCap = Balance.offlineCapHours * 3600
        XCTAssertEqual(report?.credited, expectedCap)
        XCTAssertEqual(report?.wasCapped, true)
        XCTAssertEqual(report?.coins ?? 0, rate * expectedCap * Balance.offlineEfficiency, accuracy: 1)
    }

    func testVIPRaisesTheOfflineCap() {
        var state = staffedState()
        state.entitlements.vip = true
        state.lastSeen = Date()

        let report = OfflineEarnings.compute(state: state, now: state.lastSeen.addingTimeInterval(10 * 3600))
        XCTAssertEqual(report?.wasCapped, false, "10h is inside the VIP window")
        XCTAssertEqual(report?.credited ?? 0, 10 * 3600, accuracy: 1)
    }

    // MARK: Daily rewards

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ offset: Int) -> Date {
        cal.startOfDay(for: Date()).addingTimeInterval(Double(offset) * 86400 + 3600 * 9)
    }

    func testFirstEverLoginOffersDayOne() {
        let state = GameState.newGame()
        XCTAssertEqual(DailyRewards.status(state: state, now: day(0), calendar: cal), .available(day: 1))
    }

    func testClaimingLocksOutTheRestOfTheDay() {
        var state = GameState.newGame()
        XCTAssertNotNil(DailyRewards.claim(state: &state, now: day(0), calendar: cal))

        guard case .claimed(let next, _) = DailyRewards.status(state: state, now: day(0), calendar: cal) else {
            return XCTFail("expected the calendar to be locked after claiming")
        }
        XCTAssertEqual(next, 2)
        XCTAssertNil(DailyRewards.claim(state: &state, now: day(0), calendar: cal),
                     "a second claim on the same day must be refused")
    }

    func testConsecutiveDaysAdvanceTheStreak() {
        var state = GameState.newGame()
        for expected in 1...5 {
            let payout = DailyRewards.claim(state: &state, now: day(expected - 1), calendar: cal)
            XCTAssertEqual(payout?.day, expected)
        }
        XCTAssertEqual(DailyRewards.status(state: state, now: day(5), calendar: cal), .available(day: 6))
    }

    func testMissingADayResetsToDayOne() {
        var state = GameState.newGame()
        DailyRewards.claim(state: &state, now: day(0), calendar: cal)
        DailyRewards.claim(state: &state, now: day(1), calendar: cal)
        XCTAssertEqual(state.daily.currentDay, 3)

        // Skip a day entirely.
        XCTAssertEqual(DailyRewards.status(state: state, now: day(3), calendar: cal), .available(day: 1))
        let payout = DailyRewards.claim(state: &state, now: day(3), calendar: cal)
        XCTAssertEqual(payout?.day, 1)
    }

    func testCalendarWrapsAfterTheSeventhDay() {
        var state = GameState.newGame()
        for index in 0..<7 {
            DailyRewards.claim(state: &state, now: day(index), calendar: cal)
        }
        XCTAssertEqual(state.daily.currentDay, 1, "the cycle should start over")
    }

    func testGrandPrizePaysGemsAndCoins() {
        var state = staffedState(level: 40)
        state.daily.currentDay = 7
        state.daily.lastClaimedDay = cal.startOfDay(for: day(-1))
        let gemsBefore = state.gems

        let payout = DailyRewards.claim(state: &state, now: day(0), calendar: cal)
        XCTAssertEqual(payout?.gems, 65)
        XCTAssertGreaterThan(payout?.coins ?? 0, 0)
        XCTAssertEqual(state.gems, gemsBefore + 65)
    }

    func testCoinRewardNeverFallsBelowTheFloor() {
        // A brand-new account earns nothing per second, so the floor is what it gets.
        var state = GameState.newGame()
        let payout = DailyRewards.claim(state: &state, now: day(0), calendar: cal)
        XCTAssertEqual(payout?.coins, DailyRewards.minimumCoins(day: 1))
    }

    // MARK: Boosts

    func testBoostsStackByExtendingDuration() {
        var state = GameState.newGame()
        let now = state.now
        Boosts.add(BoostState(id: "x", label: "×2", multiplier: 2, expiry: now.addingTimeInterval(600)), to: &state)
        Boosts.add(BoostState(id: "x", label: "×2", multiplier: 2, expiry: now.addingTimeInterval(600)), to: &state)

        XCTAssertEqual(state.boosts.count, 1, "same id should extend, not duplicate")
        XCTAssertEqual(state.boosts[0].remaining(at: now), 1200, accuracy: 2)
    }

    func testExpiredBoostsAreDroppedAndStopCounting() {
        var state = GameState.newGame()
        state.boosts = [BoostState(id: "old", label: "×5", multiplier: 5,
                                   expiry: state.now.addingTimeInterval(-1))]
        XCTAssertEqual(state.globalMultiplier, 1, accuracy: 1e-9)

        Boosts.prune(&state)
        XCTAssertTrue(state.boosts.isEmpty)
    }

    func testGlobalMultiplierCombinesBoostsStarsAndVIP() {
        var state = GameState.newGame()
        state.lifetimeStars = 50
        state.entitlements.vip = true                     // +25%
        state.boosts = [BoostState(id: "b", label: "×2", multiplier: 2,
                                   expiry: state.now.addingTimeInterval(600))]
        let expected = 2 * Balance.starMultiplier(stars: 50) * 1.25
        XCTAssertEqual(state.globalMultiplier, expected, accuracy: 1e-9)
    }

    // MARK: Engine

    @MainActor
    func testBuyingDeductsCoinsAndAddsLevels() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        engine.addCoins(1_000)
        engine.buyQuantity = .x10

        let before = engine.state.coins
        let price = engine.price(for: 0)
        XCTAssertTrue(engine.buy(station: 0))
        XCTAssertEqual(engine.state.venues[0].stations[0].level, 11)
        XCTAssertEqual(engine.state.coins, before - price, accuracy: 1e-6)
    }

    @MainActor
    func testBuyingIsRefusedWhenBroke() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        engine.buyQuantity = .x100
        XCTAssertFalse(engine.buy(station: 0))
        XCTAssertEqual(engine.state.venues[0].stations[0].level, 1)
    }

    @MainActor
    func testTapStartsACycleAndPayoutLandsOnCompletion() {
        var state = GameState.newGame()
        pinClock(&state, hour: 10)
        let engine = GameEngine(state: state, startTimers: false, persistence: EphemeralPersistence())
        let spec = Balance.venue(0).stations[0]

        XCTAssertTrue(engine.tap(station: 0))
        XCTAssertFalse(engine.tap(station: 0), "a running station ignores further taps")

        engine.advance(by: spec.baseCycle + 0.01)
        // Both taps fed the combo, so the payout carries its multiplier.
        let expectedCombo = 1 + 2 * ActivePlay.comboPerStep
        XCTAssertEqual(engine.state.coins, spec.baseRevenue * expectedCombo, accuracy: 1e-6)
        XCTAssertFalse(engine.state.venues[0].stations[0].isRunning,
                       "an unstaffed station stops after one cycle")
    }

    @MainActor
    func testStaffedStationRunsWithoutInput() {
        var state = GameState.newGame()
        pinClock(&state, hour: 10)
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let engine = GameEngine(state: state, startTimers: false, persistence: EphemeralPersistence())
        let spec = Balance.venue(0).stations[0]

        // Three whole cycles inside one advance - the closed-form completion path.
        engine.advance(by: spec.baseCycle * 3)
        XCTAssertEqual(engine.state.coins, spec.baseRevenue * 3, accuracy: 1e-6)
    }

    @MainActor
    func testUnlockingAVenueChargesCoinsAndOpensAStation() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        let venue = Balance.venue(1)
        engine.addCoins(venue.unlockCost)

        XCTAssertTrue(engine.unlock(venue))
        XCTAssertTrue(engine.state.venues[1].unlocked)
        XCTAssertEqual(engine.state.venues[1].stations[0].level, 1)
        XCTAssertEqual(engine.state.currentVenue, 1)
        XCTAssertEqual(engine.state.coins, 0, accuracy: 1e-6)
    }

    @MainActor
    func testPrestigeResetsTheBoardButKeepsStarsAndGems() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        engine.addCoins(4e12)
        engine.buyQuantity = .x10
        engine.buy(station: 0)
        engine.addGems(40)

        let expected = engine.pendingStars
        XCTAssertGreaterThan(expected, 0)

        let awarded = engine.prestige()
        XCTAssertEqual(awarded, expected)
        XCTAssertEqual(engine.state.stars, expected)
        XCTAssertEqual(engine.state.coins, 0)
        XCTAssertEqual(engine.state.venues[0].stations[0].level, 1, "the board resets")
        XCTAssertEqual(engine.state.gems, 65, "gems survive a franchise reset")
        XCTAssertEqual(engine.pendingStars, 0, "stars cannot be claimed twice")
    }

    @MainActor
    func testCanPrestigeWithZeroLifetimeStarsStillSurfacesAWayIntoTheSheet() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        engine.addCoins(Balance.minimumLifetimeForPrestige)

        XCTAssertTrue(engine.canPrestige, "a fresh save that hit the threshold should be prestige-eligible")
        XCTAssertEqual(engine.state.lifetimeStars, 0, "no franchise has happened yet")

        // Mirrors the HUD's entry-point condition (HUDView.swift) - it must not depend on
        // lifetimeStars alone, since that's the reward FOR prestiging, not a precondition.
        let hudShowsFranchiseEntryPoint = engine.state.lifetimeStars > 0 || engine.canPrestige
        XCTAssertTrue(hudShowsFranchiseEntryPoint,
                      "first-time players need a way into the Franchise sheet before their first prestige")
    }

    @MainActor
    func testShouldNudgePrestigeFiresForAFirstTimeEligiblePlayerRegardlessOfBoardState() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        engine.addCoins(Balance.minimumLifetimeForPrestige)

        XCTAssertEqual(engine.state.prestigeCount, 0)
        XCTAssertFalse(engine.boardIsFullyBuiltOut, "a single fresh station isn't a built-out board")
        XCTAssertTrue(engine.shouldNudgePrestige,
                      "first-time eligibility should nudge on its own, independent of the board")
    }

    @MainActor
    func testShouldNudgePrestigeClearsRightAfterPrestigingAndReturnsOncePlateauedAgain() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        engine.addCoins(Balance.minimumLifetimeForPrestige)
        engine.prestige()

        XCTAssertFalse(engine.canPrestige, "no new stars have accrued since the prestige that just happened")
        XCTAssertFalse(engine.shouldNudgePrestige)

        // Earn enough again post-prestige to become eligible a second time, and fully build
        // out the reset board - a repeat player who plateaus again should be re-nudged.
        engine.addCoins(Balance.minimumLifetimeForPrestige * 4)
        engine.buyQuantity = .x1
        for spec in Balance.venue(0).stations {
            engine.buy(station: spec.id)
            engine.hireManager(for: spec.id, free: true)
        }
        // Spend the rest of the windfall down so the next venue is genuinely unaffordable -
        // otherwise the board reads as "built out" but there's still an obvious next move. A
        // MAX buy on each station in turn drains the pile close enough to zero that what's
        // left can't cover venue 2's unlock cost.
        engine.buyQuantity = .max
        for spec in Balance.venue(0).stations {
            engine.buy(station: spec.id)
        }

        XCTAssertTrue(engine.canPrestige)
        XCTAssertTrue(engine.boardIsFullyBuiltOut)
        XCTAssertTrue(engine.shouldNudgePrestige, "plateauing again after a first prestige should re-nudge")
    }

    @MainActor
    func testBoardIsFullyBuiltOutRequiresEveryOwnedStationStaffed() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        XCTAssertFalse(engine.boardIsFullyBuiltOut, "station 0 is owned but unstaffed on a fresh save")

        engine.hireManager(for: 0, free: true)
        XCTAssertFalse(engine.boardIsFullyBuiltOut, "stations 1-5 aren't even owned yet")
    }

    @MainActor
    func testPrestigeIsRefusedBelowTheThreshold() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        engine.addCoins(1_000)
        XCTAssertFalse(engine.canPrestige)
        XCTAssertEqual(engine.prestige(), 0)
    }

    @MainActor
    func testSpendingGemsRequiresABalance() {
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        XCTAssertFalse(engine.spendGems(1_000))
        XCTAssertTrue(engine.spendGems(25))
        XCTAssertEqual(engine.state.gems, 0)
    }

    // MARK: Save round-trip

    func testSaveSurvivesEncodingAndDecoding() throws {
        var state = staffedState(level: 33)
        state.gems = 512
        state.stars = 7
        state.entitlements.vip = true
        state.daily.currentDay = 4

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var restored = try decoder.decode(GameState.self, from: encoder.encode(state))
        restored.reconcileWithCatalog()

        XCTAssertEqual(restored.gems, 512)
        XCTAssertEqual(restored.stars, 7)
        XCTAssertTrue(restored.entitlements.vip)
        XCTAssertEqual(restored.daily.currentDay, 4)
        XCTAssertEqual(restored.venues[0].stations[0].level, 33)
    }

    func testReconcileFillsInVenuesAddedSinceTheSaveWasWritten() {
        var state = GameState.newGame()
        state.venues.removeLast(2)          // simulate an older save
        state.reconcileWithCatalog()

        XCTAssertEqual(state.venues.count, Balance.venues.count)
        XCTAssertFalse(state.venues.last!.unlocked)
        XCTAssertEqual(state.venues.last!.stations.count, 6)
    }
}
