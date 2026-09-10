import XCTest
@testable import Fable

/// Franchise Vouchers: a bankable consumable granted once per prestige and rarely mid-play,
/// spent for one random hour-long effect. Covers the weighted table, the inventory cap, the
/// drop cooldown, the prestige hook, and each effect's real mechanical consequence.
final class FranchiseVoucherTests: XCTestCase {

    @MainActor
    private func engine(_ state: GameState = .newGame()) -> GameEngine {
        GameEngine(state: state, startTimers: false, persistence: EphemeralPersistence())
    }

    // MARK: Effect table

    func testEffectWeightsArePositiveAndRushHourIsTheCommonResult() {
        for effect in FranchiseVoucher.Effect.allCases {
            XCTAssertGreaterThan(effect.weight, 0, "\(effect) must have a real chance of coming up")
        }
        XCTAssertGreaterThan(FranchiseVoucher.Effect.rushHour.weight, FranchiseVoucher.Effect.luckyHour.weight,
                             "Rush Hour is the plain, safe result - it should lead the table")
        XCTAssertGreaterThan(FranchiseVoucher.Effect.rushHour.weight, FranchiseVoucher.Effect.allHandsOnDeck.weight)
    }

    /// Same shape as `Tools.roll`'s own determinism tests - `random` is a single pre-rolled
    /// value, so the whole weighted walk is checkable without touching live RNG.
    func testRollEffectWalksTheWeightedTableDeterministically() {
        let all = FranchiseVoucher.Effect.allCases
        let total = all.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(FranchiseVoucher.rollEffect(random: 0), .rushHour, "the very start of the table")
        // Just short of Rush Hour's own slice.
        let rushShare = FranchiseVoucher.Effect.rushHour.weight / total
        XCTAssertEqual(FranchiseVoucher.rollEffect(random: rushShare - 0.001), .rushHour)
        XCTAssertEqual(FranchiseVoucher.rollEffect(random: rushShare + 0.001), .luckyHour,
                       "just past Rush Hour's slice, Lucky Hour's begins")
        XCTAssertEqual(FranchiseVoucher.rollEffect(random: 0.9999), .allHandsOnDeck,
                       "the very end of the table lands the last entry")
    }

    // MARK: Inventory cap

    /// However many prestiges or lucky drops land, the bank never holds more than
    /// `FranchiseVoucher.inventoryCap` - see that constant's doc comment for why 3.
    @MainActor
    func testInventoryCapsAtThreeAndFurtherGrantsAreLost() {
        let e = engine()
        for _ in 0..<(FranchiseVoucher.inventoryCap + 10) {
            e.debugGrantFranchiseVoucher()
        }
        XCTAssertEqual(e.state.franchiseVouchers, FranchiseVoucher.inventoryCap)
    }

    // MARK: Prestige grant

    @MainActor
    func testPrestigeGrantsExactlyOneFranchiseVoucher() {
        var state = GameState.newGame()
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        let e = engine(state)
        e.debugUnlockAllVenuesAndStations()
        XCTAssertEqual(e.state.franchiseVouchers, 0)

        let awarded = e.prestige()
        XCTAssertGreaterThan(awarded, 0, "sanity check: the prestige itself must have gone through")
        XCTAssertEqual(e.state.franchiseVouchers, 1, "one voucher per franchise")
    }

    /// A player who never spends down to make room does not get an ever-growing pile - the
    /// franchise's own voucher is simply lost once the bank is already full, same as any
    /// other grant past the cap.
    @MainActor
    func testPrestigeDoesNotExceedTheInventoryCapWhenAlreadyFull() {
        var state = GameState.newGame()
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        let e = engine(state)
        for _ in 0..<FranchiseVoucher.inventoryCap { e.debugGrantFranchiseVoucher() }
        e.debugUnlockAllVenuesAndStations()

        XCTAssertGreaterThan(e.prestige(), 0, "sanity check: the prestige itself must have gone through")
        XCTAssertEqual(e.state.franchiseVouchers, FranchiseVoucher.inventoryCap)
    }

    // MARK: Drop-rate and cooldown

    /// Mirrors `testGoldenCustomerPaysOutAndClearsItself`'s brute-force approach: at 0.5% per
    /// completed station action, 5,000 tries makes a miss astronomically unlikely
    /// ((1-0.005)^5000 ≈ 10^-11) without pinning the RNG.
    @MainActor
    func testRareStationDropEventuallyFiresThenRespectsItsCooldown() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 40
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        var attempts = 0
        while e.state.franchiseVouchers == 0 && attempts < 5_000 {
            e.advance(by: 10)
            attempts += 1
        }
        XCTAssertGreaterThan(e.state.franchiseVouchers, 0,
                             "0.5% per completed action should land within 5,000 tries")

        // Immediately after a drop, the shared cooldown blocks another - hundreds more
        // completed actions inside the window must not move the count.
        let afterFirst = e.state.franchiseVouchers
        for _ in 0..<300 { e.advance(by: 10) }
        XCTAssertEqual(e.state.franchiseVouchers, afterFirst, "still inside voucherDropCooldown")

        // Skip past the cooldown - it can roll again.
        e.debugAdvanceClock(seconds: ActivePlay.voucherDropCooldown + 1)
        attempts = 0
        while e.state.franchiseVouchers == afterFirst && attempts < 5_000 {
            e.advance(by: 10)
            attempts += 1
        }
        XCTAssertGreaterThan(e.state.franchiseVouchers, afterFirst,
                             "cooldown cleared - a second drop should eventually land")
    }

    /// Locks in the judgment-call numbers themselves, same spirit as
    /// `DepthSystemsTests.testDropMomentChancesStayRareAndOrdered` - a future retune should be
    /// a deliberate edit here, not a silent drift.
    func testDropTuningStaysInTheDocumentedRange() {
        XCTAssertEqual(ActivePlay.voucherDropBaseChance, 0.005)
        XCTAssertGreaterThanOrEqual(ActivePlay.voucherDropCooldown, 60)
        XCTAssertLessThanOrEqual(ActivePlay.voucherDropCooldown, 90)
    }

    // MARK: Using a voucher

    @MainActor
    func testUsingAVoucherWithNoneBankedDoesNothing() {
        let e = engine()
        XCTAssertNil(e.useFranchiseVoucher())
        XCTAssertNil(e.pendingVoucherEffect)
    }

    @MainActor
    func testUsingAVoucherSpendsExactlyOneAndPublishesTheRolledEffect() {
        var state = GameState.newGame()
        state.franchiseVouchers = 3
        let e = engine(state)

        let effect = e.useFranchiseVoucher()
        XCTAssertNotNil(effect)
        XCTAssertEqual(e.state.franchiseVouchers, 2, "exactly one spent, regardless of which effect it rolled")
        XCTAssertEqual(e.pendingVoucherEffect, effect, "drives the reveal sheet - see RootView")
    }

    /// Rolls until the engine's own (unseeded) RNG lands a specific effect, spending from a
    /// large pre-seeded pile rather than the real 3-item cap - the cap has its own dedicated
    /// tests above, this is only about exercising each effect's real consequence.
    @MainActor
    private func engineHavingRolled(_ target: FranchiseVoucher.Effect) -> GameEngine {
        var state = GameState.newGame()
        state.franchiseVouchers = 1_000
        let e = engine(state)
        for _ in 0..<1_000 {
            guard e.state.franchiseVouchers > 0 else { break }
            if e.useFranchiseVoucher() == target { return e }
        }
        XCTFail("did not roll \(target) in 1,000 tries - check FranchiseVoucher.Effect's weights")
        return e
    }

    // MARK: Rush Hour Voucher effect

    /// "Just an addBoost call exactly like claimFreeBoost (Coffee Break)" - same mechanism,
    /// so this checks the same things `testCoffeeBreakIsFreeAndGoesOnCooldown` does.
    @MainActor
    func testRushHourVoucherAppliesTheSameBoostMechanismAsCoffeeBreak() {
        let e = engineHavingRolled(.rushHour)
        let boost = e.state.activeBoosts.first { $0.id == FranchiseVoucher.rushHourBoostID }
        XCTAssertEqual(boost?.multiplier, FranchiseVoucher.rushHourMultiplier)
        XCTAssertEqual(boost?.remaining(at: e.state.now) ?? 0,
                       FranchiseVoucher.effectDurationHours * 3600, accuracy: 2)
    }

    // MARK: Lucky Hour effect

    @MainActor
    func testLuckyHourActivatesImmediatelyAndExpiresAfterOneHour() {
        let e = engineHavingRolled(.luckyHour)
        XCTAssertTrue(e.isLuckyHourActive)
        XCTAssertEqual(e.effectiveBoostedLegendaryChance, FranchiseVoucher.luckyHourLegendaryChance)

        e.debugAdvanceClock(seconds: FranchiseVoucher.effectDurationHours * 3600 + 1)
        XCTAssertFalse(e.isLuckyHourActive)
        XCTAssertEqual(e.effectiveBoostedLegendaryChance, 0, "expired - no more nudge than an ordinary roll")
    }

    /// The permanent Debug toggle and the temporary Lucky Hour effect both claim a slice of
    /// the same `Tools.roll` range (see that function's own doc comment) - `max`, not
    /// addition, is what keeps a combined claim from exceeding a real slice of 0...1.
    @MainActor
    func testLuckyHourAndTheDebugLuckToggleCombineWithMaxNotAddition() {
        let e = engineHavingRolled(.luckyHour)
        // goldSpatulaLuckBoostEnabled is backed by the real UserDefaults.standard (a per-device
        // setting, not save data - see its own doc comment), so this MUST be restored, or a
        // test run leaves the toggle flipped on for every later test and any local dev build
        // sharing the same machine's defaults.
        let originalToggle = e.goldSpatulaLuckBoostEnabled
        defer { e.goldSpatulaLuckBoostEnabled = originalToggle }

        e.goldSpatulaLuckBoostEnabled = true
        XCTAssertEqual(e.effectiveBoostedLegendaryChance, max(0.05, FranchiseVoucher.luckyHourLegendaryChance),
                       "both active at once must not simply add together")
    }

    // MARK: All Hands on Deck effect

    @MainActor
    func testAllHandsOnDeckActivatesImmediatelyAndExpiresAfterOneHour() {
        let e = engineHavingRolled(.allHandsOnDeck)
        XCTAssertEqual(e.allHandsOnDeckMultiplier, FranchiseVoucher.allHandsMultiplier)

        e.debugAdvanceClock(seconds: FranchiseVoucher.effectDurationHours * 3600 + 1)
        XCTAssertEqual(e.allHandsOnDeckMultiplier, 1, "expired - back to no bonus")
    }

    /// The whole point of this effect: it multiplies a STAFFED station's payout...
    @MainActor
    func testAllHandsOnDeckMultipliesStaffedStationIncome() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 40
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)

        let without = engine(state)
        let before1 = without.state.coins
        without.advance(by: 5)
        let earnedWithout = without.state.coins - before1
        XCTAssertGreaterThan(earnedWithout, 0, "sanity check: the station must actually be earning")

        state.allHandsOnDeckExpiresAt = state.now.addingTimeInterval(3600)
        let with = engine(state)
        let before2 = with.state.coins
        with.advance(by: 5)
        let earnedWith = with.state.coins - before2

        XCTAssertEqual(earnedWith, earnedWithout * FranchiseVoucher.allHandsMultiplier,
                       accuracy: max(earnedWithout * 0.01, 0.01))
    }

    /// ...but leaves a manually-tapped (unstaffed) station's payout alone - "as opposed to
    /// tap-driven income" is the entire distinction this effect is supposed to draw.
    @MainActor
    func testAllHandsOnDeckDoesNotMultiplyTapDrivenIncome() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 40 // owned, deliberately never staffed

        let without = engine(state)
        _ = without.tap(station: 0)
        let before1 = without.state.coins
        without.advance(by: 60)
        let earnedWithout = without.state.coins - before1
        XCTAssertGreaterThan(earnedWithout, 0, "sanity check: the tapped cycle must actually complete")

        state.allHandsOnDeckExpiresAt = state.now.addingTimeInterval(3600)
        let with = engine(state)
        _ = with.tap(station: 0)
        let before2 = with.state.coins
        with.advance(by: 60)
        let earnedWith = with.state.coins - before2

        XCTAssertEqual(earnedWith, earnedWithout, accuracy: max(earnedWithout * 0.01, 0.01),
                       "All Hands on Deck must not touch tap-driven income")
    }

    // MARK: Persistence

    /// Same reasoning as every hand-written GameState decoder field: a save from before this
    /// feature shipped must still load, not throw and wipe the whole save.
    func testFieldsDefaultForSavesFromBeforeTheyExisted() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
        {"schemaVersion": 2, "coins": 0, "gems": 25}
        """.data(using: .utf8)!

        let state = try decoder.decode(GameState.self, from: json)
        XCTAssertEqual(state.franchiseVouchers, 0)
        XCTAssertEqual(state.luckyHourExpiresAt, .distantPast)
        XCTAssertEqual(state.allHandsOnDeckExpiresAt, .distantPast)
    }

    func testFieldsRoundTripThroughEncodeDecode() throws {
        var state = GameState.newGame()
        state.franchiseVouchers = 2
        state.luckyHourExpiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        state.allHandsOnDeckExpiresAt = Date(timeIntervalSince1970: 1_800_003_600)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameState.self, from: encoder.encode(state))

        XCTAssertEqual(decoded.franchiseVouchers, 2)
        XCTAssertEqual(decoded.luckyHourExpiresAt.timeIntervalSince1970,
                       state.luckyHourExpiresAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.allHandsOnDeckExpiresAt.timeIntervalSince1970,
                       state.allHandsOnDeckExpiresAt.timeIntervalSince1970, accuracy: 1)
    }
}
