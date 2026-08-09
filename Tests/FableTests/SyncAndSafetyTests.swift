import XCTest
@testable import Fable

/// Covers the two P0 pure functions from the August review: the Game Center score clamp
/// (a `Double` -> `Int` conversion that used to be able to trap) and the cloud-save
/// "which device is further along" ordering (which used to mis-rank Legacy resets and
/// corruption-repaired saves).
final class SyncAndSafetyTests: XCTestCase {

    // MARK: Game Center score clamp

    func testLeaderboardScoreNeverTrapsOnHugeEarnings() {
        // The historical crash: Double(Int.max) rounds up to 2^63, out of Int range.
        XCTAssertEqual(GameCenterService.leaderboardScore(lifetimeEarnings: Double(Int.max)),
                       Int(9.2e18))
        XCTAssertEqual(GameCenterService.leaderboardScore(lifetimeEarnings: 1e40), Int(9.2e18))
        XCTAssertEqual(GameCenterService.leaderboardScore(lifetimeEarnings: .infinity), 0)
        XCTAssertEqual(GameCenterService.leaderboardScore(lifetimeEarnings: .nan), 0)
        XCTAssertEqual(GameCenterService.leaderboardScore(lifetimeEarnings: -5), 0)
    }

    func testLeaderboardScorePassesOrdinaryValuesThrough() {
        XCTAssertEqual(GameCenterService.leaderboardScore(lifetimeEarnings: 123_456), 123_456)
        XCTAssertEqual(GameCenterService.leaderboardScore(lifetimeEarnings: 1e15), 1_000_000_000_000_000)
    }

    // MARK: Cloud-save ordering

    private func save(legacy: Int = 0, stars: Int = 0, earnings: Double = 0,
                      prestiges: Int = 0, researchRanks: Int = 0) -> GameState {
        var state = GameState.newGame()
        state.legacy.level = legacy
        state.lifetimeStars = stars
        state.lifetimeEarnings = earnings
        state.prestigeCount = prestiges
        if researchRanks > 0 { state.research = ["prep": researchRanks] }
        return state
    }

    func testLegacyResetDeviceBeatsStaleHighStarRemote() {
        // The device that just performed a Legacy reset has zero stars BY DESIGN - it must
        // still outrank a stale pre-reset save from another device.
        let justReset = save(legacy: 1, stars: 0, earnings: 0)
        let staleRemote = save(legacy: 0, stars: 100_000, earnings: 1e15, prestiges: 9)
        XCTAssertTrue(CloudSaveService.isAhead(justReset, of: staleRemote))
        XCTAssertFalse(CloudSaveService.isAhead(staleRemote, of: justReset))
    }

    func testCorruptionClampedTieFallsThroughToResearch() {
        // Two saves repaired by the decode clamp tie exactly on stars and earnings; the
        // one with more research bought must win instead of the conflict being invisible.
        let a = save(stars: Balance.maxSaneLifetimeStars,
                     earnings: Balance.maxSaneLifetimeEarnings, prestiges: 4, researchRanks: 6)
        let b = save(stars: Balance.maxSaneLifetimeStars,
                     earnings: Balance.maxSaneLifetimeEarnings, prestiges: 4, researchRanks: 2)
        XCTAssertTrue(CloudSaveService.isAhead(a, of: b))
        XCTAssertFalse(CloudSaveService.isAhead(b, of: a))
    }

    func testPrestigeCountBreaksEqualEarningsTie() {
        let a = save(stars: 500, earnings: 1e12, prestiges: 3)
        let b = save(stars: 500, earnings: 1e12, prestiges: 1)
        XCTAssertTrue(CloudSaveService.isAhead(a, of: b))
    }

    // MARK: automatedRate parity with globalMultiplier

    func testAutomatedRateIncludesLegacyMultiplier() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let base = state.automatedRate
        XCTAssertGreaterThan(base, 0)
        state.legacy.level = 1
        XCTAssertEqual(state.automatedRate, base * Balance.legacyMultiplier(level: 1),
                       accuracy: base * 0.0001,
                       "offline pay, quests, and time warps all price off automatedRate - it must scale with Legacy like live income does")
    }

    // MARK: Daily rewards route through the shared coin path

    @MainActor
    func testDailyCoinRewardCountsTowardLeagueAndEarnQuests() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        state.quests = [ActiveQuest(id: "q", kind: .earn, target: 1e12, progress: 0,
                                    rewardGems: 1, rewardSeconds: 60)]
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        let leagueBefore = engine.state.league.score
        let payout = engine.claimDaily()
        XCTAssertNotNil(payout)
        XCTAssertGreaterThan(payout!.coins, 0, "day 1 of the calendar pays coins")
        XCTAssertEqual(engine.state.league.score, leagueBefore + payout!.coins,
                       "a daily reward is a coin grant like any other and must feed the league")
        XCTAssertEqual(engine.state.quests[0].progress, payout!.coins,
                       "and advance earn-quests")
    }

    func testOrdinaryProgressComparisonUnchanged() {
        let bigger = save(stars: 900, earnings: 5e12)
        let smaller = save(stars: 200, earnings: 1e12)
        XCTAssertTrue(CloudSaveService.isAhead(bigger, of: smaller))
        XCTAssertFalse(CloudSaveService.isAhead(smaller, of: bigger))
        // Identical saves: neither is ahead - no spurious conflict.
        XCTAssertFalse(CloudSaveService.isAhead(smaller, of: smaller))
    }

    // MARK: Shop catalog invariants (run everywhere, unlike the StoreKit-session tests)

    private func dollars(_ item: ShopItem) -> Double {
        Double(item.fallbackPrice.replacingOccurrences(of: "$", with: "")) ?? 0
    }

    /// Every rung of the gem ladder must be a strictly better deal than the one below it,
    /// or the pricier pack is a trap. This is the invariant the Dynasty tier was added
    /// under, and the one any future pack must keep.
    func testGemLadderValuePerDollarStrictlyRises() {
        var lastRate = 0.0
        for pack in ShopCatalog.gemPacks {
            guard case .gems(let amount) = pack.reward else {
                return XCTFail("\(pack.id) in gemPacks without a gems reward")
            }
            let rate = Double(amount) / dollars(pack)
            XCTAssertGreaterThan(rate, lastRate,
                                 "\(pack.title) pays \(rate) gems/$ - not better than the pack below it")
            lastRate = rate
        }
    }

    func testCatalogHasSeventeenUniqueProducts() {
        XCTAssertEqual(ShopCatalog.all.count, 17)
        XCTAssertEqual(Set(ShopCatalog.productIDs).count, 17, "duplicate product id")
    }

    // MARK: Mogul Pass entitlement effects

    func testMogulStacksMultiplicativelyWithVIP() {
        var state = GameState.newGame()
        state.entitlements.mogul = true
        XCTAssertEqual(state.entitlements.profitMultiplier, 1.5, accuracy: 0.0001)
        state.entitlements.vip = true
        XCTAssertEqual(state.entitlements.profitMultiplier, 1.25 * 1.5, accuracy: 0.0001,
                       "the two passes multiply - neither replaces the other")
    }

    func testMogulExtendsTheOfflineCap() {
        var state = GameState.newGame()
        let base = state.offlineCapHours
        state.entitlements.mogul = true
        XCTAssertEqual(state.offlineCapHours, base + Balance.mogulOfflineCapBonusHours)
    }

    // MARK: Goal director ladder

    func testGoalLadderWalksTheArcInOrder() {
        var state = GameState.newGame()
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "first-manager")

        state.venues[0].stations[0].level = 30
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "venue-2",
                       "one manager + Lv 30 station means the next rung is expansion")

        state.venues[1].unlocked = true
        for idx in 1...4 { state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: idx) }
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "first-franchise")

        state.prestigeCount = 1
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "first-research")

        state.research["prep"] = 1
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "all-venues")

        for v in 2...4 { state.venues[v].unlocked = true }
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "franchise-5")

        state.prestigeCount = Balance.legacyUnlockPrestigeCount
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "first-legacy")

        state.legacy.level = 3
        XCTAssertNil(GoalDirector.currentGoal(for: state), "veterans graduate off the chip")
    }

    /// An old save's entitlements block predates the whale tier entirely - it must decode
    /// with both new flags off, not fail or default on.
    func testOldEntitlementsDecodeWithoutWhaleFields() throws {
        let old = #"{"vip": true, "starterPack": false, "grandOpeningBundle": false}"#
        let decoded = try JSONDecoder().decode(Entitlements.self, from: old.data(using: .utf8)!)
        XCTAssertTrue(decoded.vip)
        XCTAssertFalse(decoded.mogul)
        XCTAssertFalse(decoded.foundersBundle)
    }
}
