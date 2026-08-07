import XCTest
@testable import Fable

/// Offline earnings, the daily-login calendar, and the engine actions that move money
/// around. These are the systems where an off-by-one costs the player real progress.
final class ProgressionTests: XCTestCase {

    private func staffedState(level: Int = 10) -> GameState {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = level
        state.venues[0].stations[0].hasManager = true
        return state
    }

    // MARK: Offline earnings

    func testOnlyStaffedStationsEarnOffline() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        XCTAssertEqual(OfflineEarnings.automatedIncomePerSecond(state), 0,
                       "an unstaffed station should not earn while the app is closed")

        state.venues[0].stations[0].hasManager = true
        XCTAssertGreaterThan(OfflineEarnings.automatedIncomePerSecond(state), 0)
    }

    func testLockedVenuesDoNotContribute() {
        var state = staffedState()
        // Staff a station in a venue that was never opened.
        state.venues[1].stations[0].level = 50
        state.venues[1].stations[0].hasManager = true
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
        XCTAssertEqual(payout?.gems, 100)
        XCTAssertGreaterThan(payout?.coins ?? 0, 0)
        XCTAssertEqual(state.gems, gemsBefore + 100)
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
        state.stars = 50                                  // +100%
        state.entitlements.vip = true                     // +25%
        state.boosts = [BoostState(id: "b", label: "×2", multiplier: 2,
                                   expiry: state.now.addingTimeInterval(600))]
        XCTAssertEqual(state.globalMultiplier, 2 * 2 * 1.25, accuracy: 1e-9)
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
        let engine = GameEngine(state: GameState.newGame(), startTimers: false, persistence: EphemeralPersistence())
        let spec = Balance.venue(0).stations[0]

        XCTAssertTrue(engine.tap(station: 0))
        XCTAssertFalse(engine.tap(station: 0), "a running station ignores further taps")

        engine.advance(by: spec.baseCycle + 0.01)
        XCTAssertEqual(engine.state.coins, spec.baseRevenue, accuracy: 1e-6)
        XCTAssertFalse(engine.state.venues[0].stations[0].isRunning,
                       "an unstaffed station stops after one cycle")
    }

    @MainActor
    func testStaffedStationRunsWithoutInput() {
        var state = GameState.newGame()
        state.venues[0].stations[0].hasManager = true
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
