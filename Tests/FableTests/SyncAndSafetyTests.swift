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
    /// or the pricier pack is a trap - the invariant any future pack must keep.
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

    func testCatalogHasTwelveUniqueProducts() {
        XCTAssertEqual(ShopCatalog.all.count, 12)
        XCTAssertEqual(Set(ShopCatalog.productIDs).count, 12, "duplicate product id")
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

    // MARK: Intro pacing gates

    @MainActor
    func testLateGameSystemsStayHiddenFromNewPlayers() {
        let fresh = GameEngine(state: GameState.newGame(), startTimers: false,
                               persistence: EphemeralPersistence())
        XCTAssertFalse(fresh.crewsRelevant, "no named managers yet - no crew board")
        XCTAssertFalse(fresh.faceOffsRelevant, "no fieldable crew - no Face-Offs")
        XCTAssertFalse(fresh.gauntletRelevant, "veteran mode waits for a first franchise")
        XCTAssertFalse(fresh.toolsRelevant, "the tool chase opens with the first franchise")
        XCTAssertFalse(fresh.seasonTwistRelevant, "twist explainer waits for festival touch")
    }

    @MainActor
    func testPacingGatesOpenWithProgress() {
        var state = GameState.newGame()
        state.recruit(specID: "sam", premium: true)
        state.recruit(specID: "otto", premium: true)
        state.prestigeCount = 1
        state.festival.tickets = 10
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        XCTAssertTrue(engine.crewsRelevant)
        XCTAssertTrue(engine.faceOffsRelevant)
        XCTAssertTrue(engine.gauntletRelevant)
        XCTAssertTrue(engine.toolsRelevant)
        XCTAssertTrue(engine.seasonTwistRelevant)
    }

    // MARK: Kitchen tools

    func testGoldSpatulaIsTheRarestAndBestDrop() {
        let spatula = Tools.tool("goldspatula")!
        XCTAssertEqual(spatula.rarity, .legendary)
        XCTAssertEqual(spatula.weight, Tools.all.map(\.weight).min(),
                       "nothing may out-rare the Gold Spatula")
        XCTAssertEqual(spatula.profitBonus, Tools.all.map(\.profitBonus).max(),
                       "and nothing may out-perk it")
        let total = Tools.all.reduce(0) { $0 + $1.weight }
        XCTAssertLessThan(spatula.weight / total, 0.01, "under 1% of drops")
    }

    func testToolRollGateAndTableAreDeterministic() {
        XCTAssertNil(Tools.roll(moment: .rushComplete, roll1: 0.99, roll2: 0.5),
                     "roll1 above the gate means no drop")
        // roll2 at the very end of the table lands the last (rarest) entry.
        XCTAssertEqual(Tools.roll(moment: .expeditionWin, roll1: 0, roll2: 0.9999)?.id,
                       "goldspatula")
        XCTAssertEqual(Tools.roll(moment: .expeditionWin, roll1: 0, roll2: 0)?.id,
                       Tools.all[0].id)
    }

    func testToolEffectsAggregateAndReachTheEconomy() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let base = state.automatedRate
        state.tools = ["goldspatula", "spoon"]
        XCTAssertEqual(state.automatedRate, base * 1.25 * 1.03, accuracy: base * 0.001,
                       "owned tools multiply into the same rate everything else uses")
        XCTAssertEqual(state.toolEffects.comboWindowBonus, 1.0)
    }

    // MARK: Perk choice budget

    @MainActor
    func testPerkChoicesCapPerRunAndResetOnPrestige() {
        var state = GameState.newGame()
        // Five stations past the first choice milestone - more candidates than budget.
        for idx in 0..<5 { state.venues[0].stations[idx].level = 100 }
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        XCTAssertEqual(engine.perkChoicesRemaining, Balance.perkChoicesPerRun)

        for idx in 0..<Balance.perkChoicesPerRun {
            XCTAssertNotNil(engine.pendingPerkLevel(venue: 0, station: idx))
            engine.choosePerk(venue: 0, station: idx, level: 100, index: 0)
        }
        XCTAssertEqual(engine.perkChoicesRemaining, 0)
        XCTAssertNil(engine.pendingPerkLevel(venue: 0, station: 4),
                     "the budget is spent - the fifth station gets no prompt this run")
        let before = engine.state.venues[0].stations[4].perks
        engine.choosePerk(venue: 0, station: 4, level: 100, index: 0)
        XCTAssertEqual(engine.state.venues[0].stations[4].perks, before,
                       "choosePerk past the cap is a no-op")

        engine.debugUnlockAllVenuesAndStations()
        _ = engine.prestige()
        XCTAssertEqual(engine.perkChoicesRemaining, Balance.perkChoicesPerRun,
                       "a fresh run gets a fresh budget")
    }

    // MARK: Expeditions

    @MainActor
    func testExpeditionLifecycleAndOddsAreHonest() {
        var state = GameState.newGame()
        for spec in ["august", "nova", "vera", "dex"] { state.recruit(specID: spec, premium: true) }
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        let bench = engine.state.unassignedManagers.prefix(3).map(\.id)

        XCTAssertFalse(engine.startExpedition(managerIDs: [bench[0]], tierID: "friendly"),
                       "a crew is exactly three")
        XCTAssertTrue(engine.startExpedition(managerIDs: Array(bench), tierID: "friendly"))
        XCTAssertFalse(engine.startExpedition(managerIDs: Array(bench), tierID: "friendly"),
                       "one face-off at a time")
        XCTAssertEqual(engine.state.unassignedManagers.count, 1,
                       "the crew is off the bench while away")
        XCTAssertNil(engine.resolveExpedition(), "can't resolve before it finishes")

        // Two legendaries + an epic (score 13.5) lock the friendly tier (difficulty 4).
        let crew = engine.state.managers.filter { bench.contains($0.id) }
        XCTAssertEqual(Expeditions.winChance(score: Expeditions.crewScore(crew),
                                             tier: Expeditions.tier("friendly")), 1)

        engine.debugCompleteExpedition()
        let gems = engine.state.gems
        guard let result = engine.resolveExpedition() else { return XCTFail("resolvable") }
        XCTAssertTrue(result.won)
        XCTAssertEqual(engine.state.gems, gems + Expeditions.tier("friendly").rewardGems)
        XCTAssertNil(engine.state.expedition)
    }

    // MARK: Contracts and the Legacy tree

    @MainActor
    func testContractIsOwedAfterPrestigeAndAppliesItsTrade() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        XCTAssertNil(engine.pendingContractOffer, "no pick owed before the first franchise")

        engine.debugUnlockAllVenuesAndStations()
        _ = engine.prestige()
        guard let offer = engine.pendingContractOffer else { return XCTFail("pick owed after") }
        XCTAssertEqual(offer.count, 3)
        XCTAssertEqual(offer[0].id, "straight", "the safe pick always leads")

        let baseRate: Double = {
            var s = engine.state
            s.activeContract = "straight"
            s.venues[0].stations[0].level = 10
            s.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
            return s.automatedRate
        }()
        var doubled = engine.state
        doubled.activeContract = "doubletime"
        doubled.venues[0].stations[0].level = 10
        doubled.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        XCTAssertEqual(doubled.automatedRate, baseRate * 2 * 0.6, accuracy: baseRate * 0.001,
                       "Double-Time: x2 speed x0.6 profit = x1.2 net rate")
    }

    @MainActor
    func testLegacyLevelOwesExactlyOneTreePick() {
        var state = GameState.newGame()
        state.prestigeCount = Balance.legacyUnlockPrestigeCount
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        XCTAssertNil(engine.pendingLegacyPerkOffer)
        _ = engine.legacyReset()
        guard let offer = engine.pendingLegacyPerkOffer else { return XCTFail("pick owed") }
        XCTAssertEqual(offer.count, 3)

        engine.chooseLegacyPerk(offer[0].id)
        XCTAssertNil(engine.pendingLegacyPerkOffer, "one level, one pick")
        XCTAssertEqual(engine.state.legacyPerks[offer[0].id], 1)
    }

    func testLegacyTreeEffectsAggregate() {
        let effects = LegacyTree.effects(taken: ["patience": 2, "negotiator": 1, "showman": 1])
        XCTAssertEqual(effects.staleGraceBonusHours, 8)
        XCTAssertEqual(effects.starAwardBonus, 0.10, accuracy: 0.0001)
        XCTAssertEqual(effects.comboCapBonus, 2)
        // Grace bonus actually moves the tax curve.
        let base = Balance.stalenessMultiplier(boardAgeHours: 12)
        let shifted = Balance.stalenessMultiplier(boardAgeHours: 12, graceBonusHours: 8)
        XCTAssertGreaterThan(base, 1)
        XCTAssertEqual(shifted, 1, "8 bonus hours means hour 12 is still inside grace")
    }

    // MARK: New retention systems

    func testStaleBoardNudgeOnlySchedulesForPrestigedPlayers() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 5
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        XCTAssertFalse(NotificationPlanner.plan(for: state, now: Date()).contains { $0.id == "board-stale" },
                       "pre-first-franchise players don't know what a reset is yet")
        state.prestigeCount = 2
        state.boardStartedAt = Date()
        XCTAssertTrue(NotificationPlanner.plan(for: state, now: Date()).contains { $0.id == "board-stale" })
    }

    @MainActor
    func testWeeklyQuestRollsOncePerWeekAndClaims() {
        var state = GameState.newGame()
        state.tutorial.skip() // the weekly challenge deliberately waits for graduation
        state.venues[0].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        // bootstrapSystems already rolled this week's quest.
        guard let weekly = engine.state.weeklyQuest else { return XCTFail("no weekly quest rolled") }
        XCTAssertEqual(weekly.kind, .serve)
        XCTAssertEqual(weekly.rewardGems, 150)

        engine.rollWeeklyQuestIfNeeded()
        XCTAssertEqual(engine.state.weeklyQuest?.id, weekly.id, "same week must not re-roll")

        XCTAssertNil(engine.claimWeeklyQuest(), "unfinished challenge can't be claimed")
        let gems = engine.state.gems
        engine.debugCompleteWeeklyQuest()
        XCTAssertNotNil(engine.claimWeeklyQuest())
        XCTAssertEqual(engine.state.gems, gems + 150)
        XCTAssertNil(engine.state.weeklyQuest, "claimed challenge clears until next week")
    }

    func testRushChainMathCapsAtThree() {
        var state = GameState.newGame()
        state.rushChain = 0
        XCTAssertEqual(chainMultiplier(state), 5.0, "no chain, base x5")
        state.rushChain = 3
        XCTAssertEqual(chainMultiplier(state), 5.0 * 1.5, "chain 3 = +50%")
    }

    private func chainMultiplier(_ state: GameState) -> Double {
        ActivePlay.rushMultiplier * (1 + 0.25 * Double(max(0, state.rushChain - 1)))
    }

    // MARK: Goal director ladder

    func testGoalLadderWalksTheArcInOrder() {
        var state = GameState.newGame()
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "first-manager")

        state.venues[0].stations[0].level = 100
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        XCTAssertEqual(GoalDirector.currentGoal(for: state)?.id, "venue-2",
                       "one manager + Lv 100 station means the next rung is expansion")

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
