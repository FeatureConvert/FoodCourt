import XCTest
@testable import Fable

/// Covers the ten depth systems: combo, rush, golden, perks, managers, research, quests,
/// recipes, festival, and league.
final class FeatureTests: XCTestCase {

    @MainActor
    private func engine(_ state: GameState = .newGame()) -> GameEngine {
        GameEngine(state: state, startTimers: false, persistence: EphemeralPersistence())
    }

    /// Builds a state with known quest slots so tests aren't at the mercy of the roll.
    private func stateWithQuests(_ quests: [ActiveQuest]) -> GameState {
        var state = GameState.newGame()
        state.quests = quests
        return state
    }

    private func quest(_ kind: QuestKind, target: Double, progress: Double = 0) -> ActiveQuest {
        ActiveQuest(id: "test-\(kind.rawValue)", kind: kind, target: target,
                    progress: progress, rewardGems: 10, rewardSeconds: 60)
    }

    // MARK: 1 - Combo

    func testComboBuildsAndCapsAtTheConfiguredCeiling() {
        var combo = ComboTracker()
        let now = Date()
        for _ in 0..<10 { combo.register(at: now) }
        XCTAssertEqual(combo.count, 10)
        XCTAssertEqual(combo.multiplier(maxSteps: 30), 1 + 10 * ActivePlay.comboPerStep, accuracy: 1e-9)

        for _ in 0..<100 { combo.register(at: now) }
        // Past the cap the multiplier stops growing even though the count keeps rising.
        XCTAssertEqual(combo.multiplier(maxSteps: 30), 1 + 30 * ActivePlay.comboPerStep, accuracy: 1e-9)
    }

    func testComboExpiresAfterItsWindow() {
        var combo = ComboTracker()
        let start = Date()
        combo.register(at: start)
        XCTAssertTrue(combo.isLive(at: start.addingTimeInterval(1)))

        let after = start.addingTimeInterval(ActivePlay.comboWindow + 0.1)
        XCTAssertFalse(combo.isLive(at: after))
        XCTAssertTrue(combo.prune(at: after))
        XCTAssertEqual(combo.count, 0)
    }

    func testComboRestartsRatherThanResumingAfterALapse() {
        var combo = ComboTracker()
        let start = Date()
        combo.register(at: start)
        combo.register(at: start)
        combo.register(at: start.addingTimeInterval(ActivePlay.comboWindow + 1))
        XCTAssertEqual(combo.count, 1, "a lapsed combo starts over")
    }

    @MainActor
    func testTappingFeedsTheComboEvenOnAStaffedStation() {
        var state = GameState.newGame()
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        XCTAssertFalse(e.tap(station: 0), "a staffed station has no manual cycle to start")
        XCTAssertEqual(e.combo.count, 1, "...but the tap still counts toward the combo")
        XCTAssertGreaterThan(e.comboMultiplier, 1)
    }

    // MARK: 2 - Rush Hour

    @MainActor
    func testRushRunsThenGoesOnCooldown() {
        let e = engine()
        XCTAssertTrue(e.rushReady)
        XCTAssertTrue(e.startRush())
        XCTAssertTrue(e.rushActive)
        XCTAssertFalse(e.rushReady, "cannot start a second rush while one is running")
        XCTAssertEqual(e.state.activeBoosts.first { $0.id == ActivePlay.rushBoostID }?.multiplier,
                       ActivePlay.rushMultiplier)
    }

    @MainActor
    func testRushCompletionCountsTowardQuestsAndTickets() {
        let e = engine()
        let ticketsBefore = e.state.festival.tickets
        e.startRush()
        // Jump past the end of the rush window.
        e.debugSkip(hours: 1)
        e.advance(by: 0.1)

        XCTAssertFalse(e.rushActive)
        XCTAssertEqual(e.state.rushesCompleted, 1)
        XCTAssertEqual(e.state.festival.tickets, ticketsBefore + Festival.ticketsPerRush)
    }

    // MARK: 3 - Golden customer

    @MainActor
    func testGoldenCustomerPaysOutAndClearsItself() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 40
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        e.state.coins > 0 ? () : e.addCoins(1)
        // Force one into existence rather than waiting on the roll.
        while e.golden == nil { e.rollGoldenCustomer() }

        let before = e.state.coins
        let earned = e.collectGolden()
        XCTAssertGreaterThan(earned, 0)
        XCTAssertEqual(e.state.coins, before + earned, accuracy: 1)
        XCTAssertNil(e.golden)
        XCTAssertEqual(e.collectGolden(), 0, "cannot collect the same VIP twice")
    }

    // MARK: 4 - Perks

    func testPerkChoicesStackMultiplicatively() {
        let chosen = [25: 0, 50: 0]     // both profit perks
        XCTAssertEqual(Perks.profitMultiplier(chosen: chosen), 2.5 * 3, accuracy: 1e-9)
        XCTAssertEqual(Perks.speedMultiplier(chosen: chosen), 1, accuracy: 1e-9)
    }

    func testDoubleServeChancesCombineAsIndependentRolls() {
        let chosen = [25: 2, 50: 2]     // 20% and 30%
        // Not 50% - it's 1 - (0.8 * 0.7).
        XCTAssertEqual(Perks.doubleServeChance(chosen: chosen), 1 - 0.8 * 0.7, accuracy: 1e-9)
    }

    func testPendingPerkAppearsOnlyOnceReachedAndClearsWhenChosen() {
        XCTAssertNil(Perks.pending(level: 24, chosen: [:]))
        XCTAssertEqual(Perks.pending(level: 25, chosen: [:]), 25)
        XCTAssertEqual(Perks.pending(level: 60, chosen: [25: 0]), 50)
        XCTAssertNil(Perks.pending(level: 60, chosen: [25: 0, 50: 1]))
    }

    @MainActor
    func testChoosingAPerkChangesTheStationMath() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 25
        let e = engine(state)

        let before = e.state.baseRevenue(venue: 0, station: 0)
        e.choosePerk(venue: 0, station: 0, level: 25, index: 0)   // +150% profit
        XCTAssertEqual(e.state.baseRevenue(venue: 0, station: 0), before * 2.5, accuracy: 1e-6)
        XCTAssertNil(e.pendingPerkLevel(venue: 0, station: 0))
    }

    // MARK: 5 - Managers

    func testManagerTraitsApplyToTheRightScope() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.venues[0].stations[1].level = 10

        let plain = state.baseRevenue(venue: 0, station: 1)
        // A venue-wide trait on station 0 should also lift station 1.
        state.hire(specID: "vera", venue: 0, station: 0)          // +25% venue profit
        XCTAssertEqual(state.baseRevenue(venue: 0, station: 1), plain * 1.25, accuracy: 1e-6)
    }

    func testStationTraitOnlyAffectsItsOwnStation() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.venues[0].stations[1].level = 10

        let ownBefore = state.baseRevenue(venue: 0, station: 0)
        let otherBefore = state.baseRevenue(venue: 0, station: 1)
        state.hire(specID: "pia", venue: 0, station: 0)           // +80% station profit

        XCTAssertEqual(state.baseRevenue(venue: 0, station: 0), ownBefore * 1.8, accuracy: 1e-6)
        XCTAssertEqual(state.baseRevenue(venue: 0, station: 1), otherBefore, accuracy: 1e-9,
                       "a station trait must not leak to its neighbours")
    }

    func testAssigningAManagerElsewhereMovesRatherThanClonesThem() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 5
        state.venues[0].stations[1].level = 5
        let manager = state.hire(specID: "sam", venue: 0, station: 0)

        state.assign(managerID: manager.id, venue: 0, station: 1)
        XCTAssertNil(state.venues[0].stations[0].managerID)
        XCTAssertEqual(state.venues[0].stations[1].managerID, manager.id)
        XCTAssertEqual(state.assignedManagerCount, 1)
    }

    func testBenchedManagersAreListedAsUnassigned() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 5
        let manager = state.hire(specID: "sam", venue: 0, station: 0)
        XCTAssertTrue(state.unassignedManagers.isEmpty)

        state.assign(managerID: nil, venue: 0, station: 0)
        XCTAssertEqual(state.unassignedManagers.map(\.id), [manager.id])
    }

    // MARK: 6 - Research

    func testResearchRespectsPrerequisites() {
        let burners = Research.node("burners")!
        XCTAssertFalse(Research.isUnlocked(burners, ranks: [:]))
        XCTAssertTrue(Research.isUnlocked(burners, ranks: ["prep": 1]))
    }

    @MainActor
    func testBuyingResearchSpendsStarsButKeepsTheEarnedMultiplier() {
        var state = GameState.newGame()
        state.stars = 50
        state.lifetimeStars = 50
        let e = engine(state)

        let multiplierBefore = Balance.starMultiplier(stars: e.state.lifetimeStars)
        let node = Research.node("prep")!
        XCTAssertTrue(e.buyResearch(node))

        XCTAssertEqual(e.state.stars, 50 - node.cost(forRank: 0))
        XCTAssertEqual(e.researchRank("prep"), 1)
        XCTAssertEqual(Balance.starMultiplier(stars: e.state.lifetimeStars), multiplierBefore,
                       "spending stars must not claw back the permanent bonus")
        XCTAssertEqual(e.state.researchEffects.profitMultiplier, 1.08, accuracy: 1e-9)
    }

    @MainActor
    func testResearchIsRefusedWithoutEnoughStars() {
        let e = engine()
        XCTAssertFalse(e.buyResearch(Research.node("prep")!))
        XCTAssertEqual(e.researchRank("prep"), 0)
    }

    func testResearchCostsRiseWithRank() {
        let node = Research.node("prep")!
        XCTAssertLessThan(node.cost(forRank: 0), node.cost(forRank: 1))
        XCTAssertLessThan(node.cost(forRank: 4), node.cost(forRank: 5))
    }

    func testOfflineCapAndEfficiencyRespondToNightShiftResearch() {
        var state = GameState.newGame()
        let baseCap = state.offlineCapHours
        state.research["keys"] = 3          // +2h each
        XCTAssertEqual(state.offlineCapHours, baseCap + 6, accuracy: 1e-9)

        state.research["handover"] = 2      // +6% each
        XCTAssertEqual(state.offlineEfficiency, Balance.offlineEfficiency + 0.12, accuracy: 1e-9)
    }

    // MARK: 7 - Quests

    @MainActor
    func testQuestSlotsAreFilledAndNeverDuplicateAKind() {
        let e = engine()
        XCTAssertEqual(e.state.quests.count, Quests.slots)
        XCTAssertEqual(Set(e.state.quests.map(\.kind)).count, Quests.slots)
    }

    @MainActor
    func testTappingAdvancesATapQuest() {
        let e = engine(stateWithQuests([
            quest(.tap, target: 10), quest(.serve, target: 10), quest(.hire, target: 2),
        ]))
        e.tap(station: 0)
        e.tap(station: 0)
        XCTAssertEqual(e.state.quests.first { $0.kind == .tap }?.progress, 2)
    }

    @MainActor
    func testClaimingAQuestPaysOutAndRerollsTheSlot() {
        let e = engine(stateWithQuests([
            quest(.tap, target: 5, progress: 5), quest(.serve, target: 10), quest(.hire, target: 2),
        ]))
        let quest = e.state.quests[0]
        XCTAssertTrue(quest.isComplete)
        let gemsBefore = e.state.gems
        let ticketsBefore = e.state.festival.tickets

        let claimed = e.claimQuest(id: quest.id)
        XCTAssertEqual(claimed?.id, quest.id)
        XCTAssertEqual(e.state.gems, gemsBefore + quest.rewardGems)
        XCTAssertEqual(e.state.festival.tickets, ticketsBefore + Festival.ticketsPerQuest)
        XCTAssertEqual(e.state.quests.count, Quests.slots, "the slot refills")
        XCTAssertFalse(e.state.quests.contains { $0.id == quest.id })
        XCTAssertEqual(e.state.questsClaimed, 1)
    }

    @MainActor
    func testIncompleteQuestsCannotBeClaimed() {
        let e = engine(stateWithQuests([
            quest(.tap, target: 5, progress: 1), quest(.serve, target: 10), quest(.hire, target: 2),
        ]))
        XCTAssertNil(e.claimQuest(id: e.state.quests[0].id))
    }

    @MainActor
    func testEarnQuestAsksForNewEarningsNotTheWholeRun() {
        // Deep into a run the target must still be reachable: progress counts from zero, so
        // folding runEarnings into the target would silently demand the run again.
        var state = GameState.newGame()
        state.runEarnings = 50_000_000
        let quest = Quests.roll(state: state, incomePerSecond: 1_000, avoiding: [.serve, .level],
                                seed: 7)
        if quest.kind == .earn {
            XCTAssertLessThan(quest.target, 10_000_000)
        }

        // Whatever the roll, an earn quest rolled at any point in a run has the same target.
        var fresh = GameState.newGame()
        fresh.runEarnings = 0
        let a = Quests.roll(state: state, incomePerSecond: 1_000, avoiding: [], seed: 42)
        let b = Quests.roll(state: fresh, incomePerSecond: 1_000, avoiding: [], seed: 42)
        XCTAssertEqual(a.kind, b.kind)
        if a.kind == .earn { XCTAssertEqual(a.target, b.target, accuracy: 1e-6) }
    }

    @MainActor
    func testHireQuestCountsTotalStaffNotJustNewHires() {
        // .hire is an absolute kind: it reads the roster total, so a quest rolled with two
        // managers already working starts at two rather than at zero.
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 5
        state.venues[0].stations[1].level = 5
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)

        let quest = Quests.roll(state: state, incomePerSecond: 0,
                                avoiding: QuestKind.allCases.filter { $0 != .hire }, seed: 3)
        XCTAssertEqual(quest.kind, .hire)
        XCTAssertEqual(quest.progress, 1, "starts from the staff already working")
        XCTAssertGreaterThan(quest.target, quest.progress)

        // Carry the same board into the engine - a fresh one would have no open station 1.
        state.quests = [quest]
        let e = engine(state)
        e.addCoins(1_000_000)
        XCTAssertTrue(e.hireManager(for: 1))
        XCTAssertEqual(e.state.quests[0].progress, 2, "progress tracks the roster total")
    }

    func testQuestTitlesAgreeWithTheirCount() {
        func title(_ kind: QuestKind, _ target: Double) -> String {
            ActiveQuest(id: "t", kind: kind, target: target, progress: 0,
                        rewardGems: 0, rewardSeconds: 0).title
        }
        XCTAssertEqual(title(.rush, 1), "Complete 1 Rush Hour")
        XCTAssertEqual(title(.rush, 2), "Complete 2 Rush Hours")
        XCTAssertEqual(title(.hire, 1), "Staff 1 station")
        XCTAssertEqual(title(.hire, 3), "Staff 3 stations")
        XCTAssertEqual(title(.serve, 1), "Serve 1 dish")
        XCTAssertEqual(title(.serve, 40), "Serve 40 dishes")
        XCTAssertEqual(title(.tap, 1), "Tap 1 time")
        XCTAssertEqual(title(.recipes, 1), "Collect 1 recipe card")
    }

    func testSeasonPassIsAConsumableSoItIsNeverRestored() {
        // A restored season pass would hand out every later season for free.
        guard let pass = ShopCatalog.item(for: Festival.premiumProductID) else {
            return XCTFail("missing Carnival Pass")
        }
        XCTAssertTrue(pass.isConsumable)
        XCTAssertFalse(ShopCatalog.offers.first { $0.reward == .vip }?.isConsumable ?? true)
        XCTAssertFalse(ShopCatalog.offers.first { $0.reward == .starterPack }?.isConsumable ?? true)
    }

    // MARK: 8 - Recipes

    func testFirstDropCreatesACardThenUpgradesIt() {
        var cards: [String: Int] = [:]
        XCTAssertEqual(Recipes.roll(cards: &cards, venue: 0, station: 0, levelsBought: 1, random: 0),
                       .newCard(venue: 0, station: 0))
        XCTAssertEqual(Recipes.roll(cards: &cards, venue: 0, station: 0, levelsBought: 1, random: 0),
                       .upgraded(venue: 0, station: 0, stars: 2))
        XCTAssertEqual(Recipes.roll(cards: &cards, venue: 0, station: 0, levelsBought: 1, random: 0),
                       .upgraded(venue: 0, station: 0, stars: 3))
        // Maxed cards convert to gems instead of a fourth star.
        XCTAssertEqual(Recipes.roll(cards: &cards, venue: 0, station: 0, levelsBought: 1, random: 0),
                       .duplicateGems(Recipes.duplicateGems))
        XCTAssertEqual(Recipes.stars(cards, venue: 0, station: 0), Recipes.maxStars)
    }

    func testDropsMissWhenTheRollIsHigh() {
        var cards: [String: Int] = [:]
        XCTAssertEqual(Recipes.roll(cards: &cards, venue: 0, station: 0, levelsBought: 1, random: 0.99),
                       .none)
        XCTAssertTrue(cards.isEmpty)
    }

    func testBulkBuysImproveTheOddsWithoutGuaranteeingADrop() {
        // Ten levels at 8% each is well under certain; the roll just below that threshold hits.
        var cards: [String: Int] = [:]
        let sixAttempts = 1 - pow(1 - Recipes.dropChance, 6.0)
        XCTAssertEqual(Recipes.roll(cards: &cards, venue: 0, station: 0,
                                    levelsBought: 100, random: sixAttempts - 0.001),
                       .newCard(venue: 0, station: 0))
        XCTAssertLessThan(sixAttempts, 1.0, "a bulk buy can still miss")
    }

    func testCompleteSetPaysTheVenueBonus() {
        var cards: [String: Int] = [:]
        for station in 0..<5 { cards[Recipes.key(venue: 0, station: station)] = 1 }
        XCTAssertFalse(Recipes.isSetComplete(cards, venue: 0))
        XCTAssertEqual(Recipes.venueMultiplier(cards, venue: 0), 1)

        cards[Recipes.key(venue: 0, station: 5)] = 1
        XCTAssertTrue(Recipes.isSetComplete(cards, venue: 0))
        XCTAssertEqual(Recipes.venueMultiplier(cards, venue: 0), 1 + Recipes.setBonus)
    }

    func testStarsRaiseThatStationsProfit() {
        var cards: [String: Int] = [:]
        cards[Recipes.key(venue: 0, station: 2)] = 2
        XCTAssertEqual(Recipes.stationMultiplier(cards, venue: 0, station: 2),
                       1 + 2 * Recipes.starProfitBonus, accuracy: 1e-9)
    }

    // MARK: 9 - Festival

    func testTierThresholdsRiseAndUnlockInOrder() {
        XCTAssertEqual(Festival.unlockedTier(tickets: 0), 0)
        let tier5 = Festival.ticketsRequired(forTier: 5)
        XCTAssertEqual(Festival.unlockedTier(tickets: tier5), 5)
        XCTAssertEqual(Festival.unlockedTier(tickets: tier5 - 1), 4)
        XCTAssertLessThan(Festival.ticketsRequired(forTier: 10),
                          Festival.ticketsRequired(forTier: 11))
    }

    func testPremiumRewardsNeedThePass() {
        var state = FestivalState()
        state.tickets = Festival.ticketsRequired(forTier: 3)
        XCTAssertTrue(Festival.canClaim(state, tier: 3, premium: false))
        XCTAssertFalse(Festival.canClaim(state, tier: 3, premium: true))

        state.premiumUnlocked = true
        XCTAssertTrue(Festival.canClaim(state, tier: 3, premium: true))
    }

    @MainActor
    func testClaimingATierIsOneShot() {
        let e = engine()
        e.awardTickets(Festival.ticketsRequired(forTier: 2))
        XCTAssertNotNil(e.claimFestival(tier: 2, premium: false))
        XCTAssertNil(e.claimFestival(tier: 2, premium: false), "already claimed")
    }

    @MainActor
    func testUnreachedTiersCannotBeClaimed() {
        let e = engine()
        XCTAssertNil(e.claimFestival(tier: 20, premium: false))
    }

    func testSeasonRolloverResetsProgressAndThePass() {
        var state = FestivalState()
        state.tickets = 900
        state.claimedFree = [1, 2, 3]
        state.premiumUnlocked = true
        state.endsAt = Date().addingTimeInterval(-1)

        XCTAssertTrue(Festival.rolloverIfNeeded(&state, now: Date()))
        XCTAssertEqual(state.seasonID, 2)
        XCTAssertEqual(state.tickets, 0)
        XCTAssertTrue(state.claimedFree.isEmpty)
        XCTAssertFalse(state.premiumUnlocked)
        XCTAssertFalse(Festival.rolloverIfNeeded(&state, now: Date()), "only rolls once")
    }

    @MainActor
    func testServingDripsTicketsSlowly() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 1
        let e = engine(state)
        XCTAssertEqual(e.state.festival.tickets, 0)

        for _ in 0..<(Festival.servesPerTicket) {
            e.tap(station: 0)
            e.advance(by: Balance.venue(0).stations[0].baseCycle + 0.01)
        }
        XCTAssertGreaterThanOrEqual(e.state.festival.tickets, 1)
    }

    // MARK: 10 - League

    func testLeagueSeedsAFullTable() {
        let state = League.newWeek(tier: .bronze, playerRate: 100, now: Date(), seasonsPlayed: 0)
        XCTAssertEqual(state.rivals.count, League.size - 1)
        XCTAssertEqual(League.standings(state).count, League.size)
        XCTAssertTrue(state.rivals.allSatisfy { $0.rate > 0 })
    }

    func testStandingsRankByScoreAndIncludeThePlayer() {
        var state = League.newWeek(tier: .bronze, playerRate: 10, now: Date(), seasonsPlayed: 0)
        state.rivals.indices.forEach { state.rivals[$0].score = 0 }
        state.score = 1_000_000

        let standings = League.standings(state)
        XCTAssertTrue(standings.first?.isPlayer == true)
        XCTAssertEqual(League.playerRank(state), 1)
        XCTAssertEqual(standings.map(\.rank), Array(1...League.size))
    }

    func testTopSevenPromoteAndBottomSevenRelegate() {
        var state = League.newWeek(tier: .silver, playerRate: 10, now: Date(), seasonsPlayed: 0)

        state.rivals.indices.forEach { state.rivals[$0].score = 0 }
        state.score = 1_000
        XCTAssertEqual(League.settle(state), .promoted(from: .silver, to: .gold, rank: 1,
                                                       gems: LeagueTier.silver.gemReward))

        state.rivals.indices.forEach { state.rivals[$0].score = 1_000_000 }
        state.score = 1
        XCTAssertEqual(League.settle(state),
                       .relegated(from: .silver, to: .bronze, rank: League.size))
    }

    func testBronzeCannotRelegateAndDiamondCannotPromote() {
        var bottom = League.newWeek(tier: .bronze, playerRate: 10, now: Date(), seasonsPlayed: 0)
        bottom.rivals.indices.forEach { bottom.rivals[$0].score = 1_000_000 }
        bottom.score = 0
        if case .relegated = League.settle(bottom) {
            XCTFail("bronze is the floor")
        }

        var top = League.newWeek(tier: .diamond, playerRate: 10, now: Date(), seasonsPlayed: 0)
        top.rivals.indices.forEach { top.rivals[$0].score = 0 }
        top.score = 1_000_000
        if case .promoted = League.settle(top) {
            XCTFail("diamond is the ceiling")
        }
    }

    func testRivalsEarnWhileTheAppIsClosed() {
        var state = League.newWeek(tier: .bronze, playerRate: 100, now: Date(), seasonsPlayed: 0)
        let before = state.rivals[0].score
        League.advanceRivals(&state, to: state.lastSettledAt.addingTimeInterval(3600))
        XCTAssertGreaterThan(state.rivals[0].score, before)
    }

    @MainActor
    func testFinishedWeekSettlesAndStartsAFreshOne() {
        var state = GameState.newGame()
        state.league = League.newWeek(tier: .bronze, playerRate: 10, now: Date(), seasonsPlayed: 0)
        state.league.endsAt = Date().addingTimeInterval(-1)
        state.league.rivals.indices.forEach { state.league.rivals[$0].score = 0 }
        state.league.score = 10_000

        let e = engine(state)
        e.settleLeagueIfFinished()

        XCTAssertNotNil(e.pendingLeagueOutcome)
        XCTAssertEqual(e.state.league.tier, .silver, "a top-7 finish promotes")
        XCTAssertEqual(e.state.league.score, 0, "the new week starts level")
        XCTAssertEqual(e.state.league.seasonsPlayed, 1)
    }

    // MARK: Prestige interaction

    @MainActor
    func testFranchiseResetKeepsTheCollectionsButClearsTheBoard() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 60
        state.venues[0].stations[0].perks = [25: 0]
        state.hire(specID: "dex", venue: 0, station: 0)
        state.recipeCards[Recipes.key(venue: 0, station: 0)] = 2
        state.research["prep"] = 3
        state.venues[1].unlocked = true

        let e = engine(state)
        e.addCoins(4e12)
        let awarded = e.prestige()
        XCTAssertGreaterThan(awarded, 0)

        // Kept: the things the player collected.
        XCTAssertEqual(e.state.managers.count, 1, "staff survive a franchise reset")
        XCTAssertEqual(e.state.managers.first?.specID, "dex")
        XCTAssertEqual(e.state.recipeCards[Recipes.key(venue: 0, station: 0)], 2)
        XCTAssertEqual(e.state.research["prep"], 3)
        XCTAssertEqual(e.state.stars, awarded)
        XCTAssertEqual(e.state.lifetimeStars, awarded)

        // Cleared: the board itself.
        XCTAssertEqual(e.state.venues[0].stations[0].level, 1)
        XCTAssertTrue(e.state.venues[0].stations[0].perks.isEmpty, "perks reset with the station")
        XCTAssertFalse(e.state.venues[0].stations[0].isStaffed, "staff return to the bench")
        XCTAssertFalse(e.state.venues[1].unlocked)
        XCTAssertEqual(e.state.coins, 0)

        // The manager is unassigned rather than deleted, so it can be put straight back to work.
        XCTAssertEqual(e.state.unassignedManagers.count, 1)
        XCTAssertEqual(e.state.assignedManagerCount, 0)
    }

    // MARK: Save migration

    func testSchemaOneSaveMigratesOntoRealManagers() throws {
        // A schema-1 payload: hasManager, no managerID, no depth-system fields at all.
        let legacy = """
        {
          "schemaVersion": 1, "coins": 500, "gems": 42, "stars": 12,
          "lifetimeEarnings": 1000, "runEarnings": 1000, "currentVenue": 0,
          "boosts": [], "entitlements": {"vip": false, "starterPack": false},
          "daily": {"currentDay": 3}, "lastSeen": "2026-08-07T12:00:00Z",
          "adAvailableAt": "2026-08-07T12:00:00Z", "timeOffset": 0,
          "venues": [
            {"unlocked": true, "stations": [
              {"level": 30, "hasManager": true, "elapsed": 0, "isRunning": true},
              {"level": 5, "hasManager": false, "elapsed": 0, "isRunning": false}
            ]}
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var state = try decoder.decode(GameState.self, from: legacy)
        state.reconcileWithCatalog()

        XCTAssertEqual(state.coins, 500)
        XCTAssertEqual(state.gems, 42)
        XCTAssertEqual(state.stars, 12)
        XCTAssertEqual(state.lifetimeStars, 12, "the permanent bonus is seeded from old stars")
        XCTAssertEqual(state.venues[0].stations[0].level, 30)

        // The old boolean became a real Trainee on the roster.
        XCTAssertTrue(state.venues[0].stations[0].isStaffed)
        XCTAssertEqual(state.managers.count, 1)
        XCTAssertEqual(state.managers.first?.specID, ManagerCatalog.traineeID)
        XCTAssertFalse(state.venues[0].stations[1].isStaffed)

        // Missing venues and every new system default cleanly.
        XCTAssertEqual(state.venues.count, Balance.venues.count)
        XCTAssertTrue(state.research.isEmpty)
        XCTAssertTrue(state.recipeCards.isEmpty)
        XCTAssertEqual(state.festival.tickets, 0)
    }

    func testNewFieldsSurviveARoundTrip() throws {
        var state = GameState.newGame()
        state.venues[0].stations[0].perks = [25: 1]
        state.hire(specID: "dex", venue: 0, station: 0)
        state.research["prep"] = 4
        state.recipeCards[Recipes.key(venue: 0, station: 0)] = 2
        state.festival.tickets = 640
        state.league.score = 12_345
        state.totalTaps = 99

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(GameState.self, from: encoder.encode(state))

        XCTAssertEqual(restored.venues[0].stations[0].perks, [25: 1])
        XCTAssertEqual(restored.managerSpec(venue: 0, station: 0)?.id, "dex")
        XCTAssertEqual(restored.research["prep"], 4)
        XCTAssertEqual(restored.recipeCards[Recipes.key(venue: 0, station: 0)], 2)
        XCTAssertEqual(restored.festival.tickets, 640)
        XCTAssertEqual(restored.league.score, 12_345)
        XCTAssertEqual(restored.totalTaps, 99)
    }
}
