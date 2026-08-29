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
        // newGame() locks Rush Hour out for a new player's first 15 minutes; this test is
        // about the readiness/cooldown mechanic itself, not that onboarding gate.
        var state = GameState.newGame()
        state.rushAvailableAt = .distantPast
        let e = engine(state)
        XCTAssertTrue(e.rushReady)
        XCTAssertTrue(e.startRush())
        XCTAssertTrue(e.rushActive)
        XCTAssertFalse(e.rushReady, "cannot start a second rush while one is running")
        XCTAssertEqual(e.state.activeBoosts.first { $0.id == ActivePlay.rushBoostID }?.multiplier,
                       ActivePlay.rushMultiplier)
    }

    @MainActor
    func testRushCompletionCountsTowardQuestsAndTickets() {
        var state = GameState.newGame()
        state.rushAvailableAt = .distantPast
        let e = engine(state)
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
        let chosen = [100: 0, 250: 0]     // both profit perks
        XCTAssertEqual(Perks.profitMultiplier(chosen: chosen), 4 * 5, accuracy: 1e-9)
        XCTAssertEqual(Perks.speedMultiplier(chosen: chosen), 1, accuracy: 1e-9)
    }

    func testDoubleServeChancesCombineAsIndependentRolls() {
        let chosen = [100: 2, 250: 2]     // 45% and 55%
        // Not 100% - it's 1 - (0.55 * 0.45).
        XCTAssertEqual(Perks.doubleServeChance(chosen: chosen), 1 - 0.55 * 0.45, accuracy: 1e-9)
    }

    func testPendingPerkAppearsOnlyOnceReachedAndClearsWhenChosen() {
        XCTAssertNil(Perks.pending(level: 99, chosen: [:]))
        XCTAssertEqual(Perks.pending(level: 100, chosen: [:]), 100)
        XCTAssertEqual(Perks.pending(level: 260, chosen: [100: 0]), 250)
        XCTAssertNil(Perks.pending(level: 260, chosen: [100: 0, 250: 1]))
    }

    @MainActor
    func testChoosingAPerkChangesTheStationMath() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 100
        let e = engine(state)

        let before = e.state.baseRevenue(venue: 0, station: 0)
        e.choosePerk(venue: 0, station: 0, level: 100, index: 0)   // +300% profit
        XCTAssertEqual(e.state.baseRevenue(venue: 0, station: 0), before * 4, accuracy: 1e-6)
        XCTAssertNil(e.pendingPerkLevel(venue: 0, station: 0))
    }

    /// A double-tap (or a second tap landing in the confirm-to-dismiss window) must not burn
    /// a second one of the run's four precious perk choices for a pick already made.
    @MainActor
    func testDoubleChoosingTheSamePerkOnlyCountsOnce() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 100
        let e = engine(state)

        e.choosePerk(venue: 0, station: 0, level: 100, index: 0)
        let usedAfterFirst = e.state.perkChoicesUsed
        let mathAfterFirst = e.state.baseRevenue(venue: 0, station: 0)

        e.choosePerk(venue: 0, station: 0, level: 100, index: 1)   // even a different index
        XCTAssertEqual(e.state.perkChoicesUsed, usedAfterFirst, "a repeat pick must not spend a second choice")
        XCTAssertEqual(e.state.venues[0].stations[0].perks[100], 0, "the original pick must stick")
        XCTAssertEqual(e.state.baseRevenue(venue: 0, station: 0), mathAfterFirst, accuracy: 1e-6)
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

    /// The "Auto-assign" button in the Staff sheet - fills every open (owned, unstaffed)
    /// station with a benched manager, first-open-station to first-available-manager.
    @MainActor
    func testAutoAssignBenchedManagersFillsOpenStationsFromTheBench() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 5
        state.venues[0].stations[1].level = 5
        state.managers.append(contentsOf: [OwnedManager.make("dex"), OwnedManager.make("sam")])
        // Both stations are being staffed for the first time, which now charges the same
        // one-time fee a fresh hire would (see GameEngine.assign) - fund it well past
        // Balance.managerCost(station 0) + Balance.managerCost(station 1) (~25.2K combined).
        state.coins = 100_000
        let e = engine(state)

        XCTAssertEqual(e.autoAssignBenchedManagers(), 2)
        XCTAssertTrue(e.state.venues[0].stations[0].isStaffed)
        XCTAssertTrue(e.state.venues[0].stations[1].isStaffed)
        XCTAssertTrue(e.state.unassignedManagers.isEmpty)
        XCTAssertEqual(e.autoAssignBenchedManagers(), 0, "no open stations or bench left")
    }

    /// The station-row UI reads `cachedModifiers`/`cachedCycleTime`/`cachedBaseRevenue`
    /// instead of recomputing the manager/research/synergy walk on every render - this
    /// checks the cache never disagrees with a fresh, uncached computation, whether or not
    /// anything has ticked yet.
    @MainActor
    func testCachedModifiersFallBackBeforeFirstTickAndAgreeAfterAdvance() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 5
        _ = state.hire(specID: "sam", venue: 0, station: 0)
        let e = engine(state)

        // Nothing has ticked yet (startTimers: false, no advance() called) - the cache is
        // empty, so this must fall back to the same number a direct computation gives.
        XCTAssertEqual(e.cachedModifiers(venue: 0, station: 0), e.state.modifiers(venue: 0, station: 0))

        // After a tick, the cache holds the value advance() itself just computed and used.
        e.advance(by: 0.05)
        XCTAssertEqual(e.cachedModifiers(venue: 0, station: 0), e.state.modifiers(venue: 0, station: 0))
        XCTAssertEqual(e.cachedCycleTime(venue: 0, station: 0),
                       e.state.cycleTime(venue: 0, station: 0), accuracy: 1e-9)
        XCTAssertEqual(e.cachedBaseRevenue(venue: 0, station: 0),
                       e.state.baseRevenue(venue: 0, station: 0), accuracy: 1e-9)

        // A later change (benching the manager, which drops the bond profit bonus) is
        // reflected as soon as the next tick recomputes it - the cache never gets stuck.
        e.assign(managerID: nil, venue: 0, station: 0)
        e.advance(by: 0.05)
        XCTAssertEqual(e.cachedModifiers(venue: 0, station: 0), e.state.modifiers(venue: 0, station: 0))
        XCTAssertEqual(e.cachedModifiers(venue: 0, station: 0).profit, 1, accuracy: 1e-9,
                       "no manager, no perks, no research - profit modifier should be back to 1")
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
        XCTAssertEqual(e.state.researchEffects.profitMultiplier, 1.04, accuracy: 1e-9)
    }

    @MainActor
    func testResearchIsRefusedWithoutEnoughStars() {
        let e = engine()
        XCTAssertFalse(e.buyResearch(Research.node("prep")!))
        XCTAssertEqual(e.researchRank("prep"), 0)
    }

    /// The "Buy All Affordable" button - greedy cheapest-first, same walk
    /// projectedResearchRanks already used for its preview number.
    @MainActor
    func testBuyAllAffordableResearchSpendsGreedilyUntilNothingElseFits() {
        var state = GameState.newGame()
        state.stars = 0
        let e = engine(state)
        XCTAssertEqual(e.buyAllAffordableResearch(), 0, "no stars, nothing to buy")

        state = GameState.newGame()
        state.stars = 1_000_000
        let rich = engine(state)
        let bought = rich.buyAllAffordableResearch()
        XCTAssertGreaterThan(bought, 0)
        XCTAssertEqual(Research.nodes.filter { rich.canBuyResearch($0) }.count, 0,
                       "must keep buying until literally nothing else is affordable")
    }

    func testResearchCostsRiseWithRank() {
        let node = Research.node("prep")!
        XCTAssertLessThan(node.cost(forRank: 0), node.cost(forRank: 1))
        XCTAssertLessThan(node.cost(forRank: 4), node.cost(forRank: 5))
    }

    func testOfflineCapAndEfficiencyRespondToNightShiftResearch() {
        var state = GameState.newGame()
        // Pin a season whose twist has no offline component (season twists rotate by id,
        // and id % 4 == 0 is Tap Frenzy) so this measures research alone.
        state.festival.seasonID = 4
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

    /// The "Claim All" button on the Quests tab - collects every finished quest slot in one
    /// tap but leaves the incomplete one running.
    @MainActor
    func testClaimAllQuestsClaimsOnlyTheCompleteOnes() {
        let e = engine(stateWithQuests([
            quest(.tap, target: 5, progress: 5), quest(.serve, target: 10, progress: 10),
            quest(.hire, target: 2, progress: 0),
        ]))
        XCTAssertEqual(e.claimAllQuests(), 2)
        XCTAssertEqual(e.state.questsClaimed, 2)
        XCTAssertEqual(e.claimAllQuests(), 0, "the hire quest is still incomplete")
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

    /// An .earn quest's target scales uncapped with the player's current income, so a
    /// long-running high-income save can roll one past Int.max. `.title` used to compute
    /// `Int(target)` unconditionally before the kind switch - crashing the instant the
    /// Goals tab tried to render the row, even though .earn never uses that value.
    func testEarnQuestTitleSurvivesATargetBeyondIntMax() {
        let quest = ActiveQuest(id: "t", kind: .earn, target: Double(Int.max) * 4,
                                 progress: 0, rewardGems: 0, rewardSeconds: 0)
        XCTAssertTrue(quest.title.hasPrefix("Earn"))
    }

    // MARK: Ad-free model

    @MainActor
    func testCoffeeBreakIsFreeAndGoesOnCooldown() {
        // newGame() locks Coffee Break out for a new player's first 15 minutes; this test is
        // about the readiness/cooldown mechanic itself, not that onboarding gate.
        var state = GameState.newGame()
        state.boostAvailableAt = .distantPast
        let e = engine(state)
        XCTAssertTrue(e.boostReady)
        XCTAssertTrue(e.claimFreeBoost(), "the boost costs nothing - there is no ad to watch")

        let boost = e.state.activeBoosts.first { $0.id == ActivePlay.freeBoostID }
        XCTAssertEqual(boost?.multiplier, ActivePlay.freeBoostMultiplier)
        XCTAssertFalse(e.boostReady)
        XCTAssertFalse(e.claimFreeBoost(), "cannot re-take it inside the cooldown")
        XCTAssertGreaterThan(e.boostCooldownRemaining, 0)
    }

    /// The cooldown starts when the boost ENDS, not when it's claimed - matching Rush
    /// Hour's own already-correct pattern (rushAvailableAt is set from rushEndsAt). Before
    /// this fix the 15-minute active window was eaten by the 30-minute cooldown instead of
    /// sitting on top of it.
    @MainActor
    func testCoffeeBreakCooldownStartsAfterTheBoostEndsNotAtActivation() {
        var state = GameState.newGame()
        state.boostAvailableAt = .distantPast
        let e = engine(state)
        let claimedAt = e.state.now
        XCTAssertTrue(e.claimFreeBoost())

        let expected = claimedAt
            .addingTimeInterval(ActivePlay.freeBoostHours * 3600)
            .addingTimeInterval(ActivePlay.freeBoostCooldownMinutes * 60)
        XCTAssertEqual(e.state.boostAvailableAt.timeIntervalSince1970, expected.timeIntervalSince1970,
                       accuracy: 1, "cooldown = full active duration + the cooldown minutes, not cooldown alone")
    }

    @MainActor
    func testOfflineDoubleIsFreeOncePerDay() {
        let e = engine()
        let report = OfflineReport(elapsed: 7200, credited: 7200, coins: 5_000,
                                   wasCapped: false, capHours: 2)

        XCTAssertTrue(e.offlineDoubleAvailable())
        let before = e.state.coins
        XCTAssertTrue(e.claimOfflineDouble(report))
        XCTAssertEqual(e.state.coins, before + 5_000, accuracy: 1)

        XCTAssertFalse(e.offlineDoubleAvailable(), "once a day")
        XCTAssertFalse(e.claimOfflineDouble(report))

        // Tomorrow it is available again.
        e.debugSkip(hours: 24)
        XCTAssertTrue(e.offlineDoubleAvailable())
    }

    @MainActor
    func testOfflineDoubleWithGemsWorksAfterTheFreeOneIsSpent() {
        // Reported live: once the free daily double was already used, the welcome-back screen
        // had no way to double at all - just "No thanks, collect" with nothing to decline.
        let e = engine()
        let report = OfflineReport(elapsed: 7200, credited: 7200, coins: 5_000,
                                   wasCapped: false, capHours: 2)
        XCTAssertTrue(e.claimOfflineDouble(report))
        XCTAssertFalse(e.offlineDoubleAvailable())

        e.addGems(1_000)
        let coinsBefore = e.state.coins
        let gemsBefore = e.state.gems
        XCTAssertTrue(e.claimOfflineDoubleWithGems(report))
        XCTAssertEqual(e.state.coins, coinsBefore + 5_000, accuracy: 1)
        XCTAssertEqual(e.state.gems, gemsBefore - GameEngine.offlineDoubleGemCost)
        // Doesn't touch the free path's own gate - it's still spent for today, not refreshed.
        XCTAssertFalse(e.offlineDoubleAvailable())

        // Not enough gems: no partial charge, no coins.
        let broke = engine()
        let coinsBeforeBroke = broke.state.coins
        XCTAssertFalse(broke.claimOfflineDoubleWithGems(report))
        XCTAssertEqual(broke.state.coins, coinsBeforeBroke, accuracy: 1)
    }

    @MainActor
    func testVIPCarriesTheCarnivalPassEverySeason() {
        let e = engine()
        e.awardTickets(Festival.ticketsRequired(forTier: 3))
        XCTAssertFalse(e.festivalPremiumActive)
        XCTAssertNil(e.claimFestival(tier: 3, premium: true))

        e.setEntitlement(vip: true)
        XCTAssertTrue(e.festivalPremiumActive)
        XCTAssertNotNil(e.claimFestival(tier: 3, premium: true))

        // Survives a season rollover, unlike a bought pass.
        let season = e.state.festival.seasonID
        e.debugSkip(hours: Festival.seasonLength / 3600 + 1)
        XCTAssertGreaterThan(e.state.festival.seasonID, season, "the season rolled")
        XCTAssertFalse(e.state.festival.premiumUnlocked, "a bought pass would have lapsed")
        XCTAssertTrue(e.festivalPremiumActive, "VIP still includes it in the new season")
    }

    /// The "Claim All" button - both tracks, every tier the ticket total has actually
    /// unlocked, and it must be idempotent (nothing left to claim on a second call).
    @MainActor
    func testClaimAllFestivalClaimsBothTracksAcrossUnlockedTiers() {
        let e = engine()
        e.setEntitlement(vip: true)
        e.awardTickets(Festival.ticketsRequired(forTier: 5))

        let claimed = e.claimAllFestival()
        XCTAssertEqual(claimed, 10, "5 tiers x free+premium")
        XCTAssertEqual(Festival.unclaimedCount(e.state.festival, premiumActive: true), 0)
        XCTAssertEqual(e.claimAllFestival(), 0, "nothing left the second time")
    }

    @MainActor
    func testServingCannotRunAwayWithTheWholeFestivalTrack() {
        // The drip scales with income, which scales without limit. The cap is what stops an
        // established player finishing a 3-day season in minutes.
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 400
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        // A full day of a very fast station.
        for _ in 0..<600 { e.advance(by: 144) }

        XCTAssertLessThanOrEqual(e.state.festival.ticketsFromServing, Festival.maxTicketsFromServing)
        XCTAssertLessThan(e.state.festival.tickets, Festival.ticketsRequired(forTier: Festival.tierCount),
                          "serving alone must not complete the track")
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
        XCTAssertTrue(Festival.canClaim(state, tier: 3, premium: false, premiumActive: false))
        XCTAssertFalse(Festival.canClaim(state, tier: 3, premium: true, premiumActive: false))

        state.premiumUnlocked = true
        XCTAssertTrue(Festival.canClaim(state, tier: 3, premium: true, premiumActive: true))
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
        let state = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        XCTAssertEqual(state.rivals.count, League.size - 1)
        XCTAssertEqual(League.standings(state).count, League.size)
        XCTAssertTrue(state.rivals.allSatisfy { $0.jitter > 0 })
    }

    func testRivalPaceTracksThePlayersCurrentRateNotAStaleSnapshot() {
        var state = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        League.advanceRivals(&state, to: state.lastSettledAt.addingTimeInterval(3600), playerRate: 10)
        let slowGain = state.rivals[0].score

        var fast = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        League.advanceRivals(&fast, to: fast.lastSettledAt.addingTimeInterval(3600), playerRate: 10_000)
        let fastGain = fast.rivals[0].score

        XCTAssertGreaterThan(fastGain, slowGain * 100,
                             "a rival's pace must scale with the player's current rate, not a rate frozen at week start")
    }

    /// Live report: 1.14M league score against a 32K second place after three minutes.
    /// Root cause - rivals raced `automatedRate`, which deliberately excludes combo/
    /// boosts/Happy Hour, while the player's real score carries all of them. Rivals now
    /// race the player's own realized score delta, so a burst of active play (bursty,
    /// well above automatedRate) pulls rivals up close behind rather than leaving them at
    /// a tiny fraction of it.
    func testRivalsRaceTheRealizedScoreNotJustAutomatedRate() {
        var state = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        let start = state.lastSettledAt
        // Automated income is nearly nothing (a fresh board), but the player is banking
        // real score fast via taps/goldens/quests - automatedRate alone can't see this.
        state.score = 1_140_000
        League.advanceRivals(&state, to: start.addingTimeInterval(180), playerRate: 1)

        let bestRivalScore = state.rivals.map(\.score).max() ?? 0
        // Old behavior pinned every rival under ~1.85x automatedRate*strength*elapsed,
        // a few hundred coins here - nowhere close to competitive with a six-figure score.
        XCTAssertGreaterThan(bestRivalScore, state.score * 0.1,
                             "at least one rival should be within striking distance of a bursty player, not a rounding error")
    }

    /// The other half: an idle/offline player must still see rivals crawl forward at
    /// automatedRate, exactly as before - recentEarnRate decays toward 0 with no score
    /// deltas to feed it, so `playerRate` remains the floor.
    func testRivalsStillPaceOffAutomatedRateWhenThePlayerIsIdle() {
        var state = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        let start = state.lastSettledAt
        // No `state.score` change between calls - the idle case.
        League.advanceRivals(&state, to: start.addingTimeInterval(1800), playerRate: 50)
        League.advanceRivals(&state, to: start.addingTimeInterval(3600), playerRate: 50)
        XCTAssertGreaterThan(state.rivals[0].score, 0)
        XCTAssertEqual(state.recentEarnRate, 0, accuracy: 1e-6,
                       "no score movement should decay the realized rate to zero, not linger")
    }

    /// Every save on disk predates recentEarnRate/scoreAtLastSync - decoding an older
    /// blob must not fail or silently reset the week.
    func testLeagueStateDecodesWithoutTheNewSyncFields() throws {
        let json = """
        {"tier": 1, "score": 4000, "rivals": [], "startedAt": "2026-01-01T00:00:00Z",
         "endsAt": "2026-01-08T00:00:00Z", "lastSettledAt": "2026-01-01T00:00:00Z",
         "seasonsPlayed": 3}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LeagueState.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(state.score, 4000)
        XCTAssertEqual(state.recentEarnRate, 0)
        XCTAssertEqual(state.scoreAtLastSync, state.score,
                       "first sync after loading an old save should diff against the current score, not 0")
    }

    func testStandingsRankByScoreAndIncludeThePlayer() {
        var state = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        state.rivals.indices.forEach { state.rivals[$0].score = 0 }
        state.score = 1_000_000

        let standings = League.standings(state)
        XCTAssertTrue(standings.first?.isPlayer == true)
        XCTAssertEqual(League.playerRank(state), 1)
        XCTAssertEqual(standings.map(\.rank), Array(1...League.size))
    }

    func testTopSevenPromoteAndBottomSevenRelegate() {
        var state = League.newWeek(tier: .silver, now: Date(), seasonsPlayed: 0)

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
        var bottom = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        bottom.rivals.indices.forEach { bottom.rivals[$0].score = 1_000_000 }
        bottom.score = 0
        if case .relegated = League.settle(bottom) {
            XCTFail("bronze is the floor")
        }

        var top = League.newWeek(tier: .diamond, now: Date(), seasonsPlayed: 0)
        top.rivals.indices.forEach { top.rivals[$0].score = 0 }
        top.score = 1_000_000
        if case .promoted = League.settle(top) {
            XCTFail("diamond is the ceiling")
        }
    }

    func testRivalsEarnWhileTheAppIsClosed() {
        var state = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
        let before = state.rivals[0].score
        League.advanceRivals(&state, to: state.lastSettledAt.addingTimeInterval(3600), playerRate: 100)
        XCTAssertGreaterThan(state.rivals[0].score, before)
    }

    @MainActor
    func testFinishedWeekSettlesAndStartsAFreshOne() {
        var state = GameState.newGame()
        state.league = League.newWeek(tier: .bronze, now: Date(), seasonsPlayed: 0)
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

    /// Live report: the Burger Shack's last station cost ~622M to staff (baseCost * a flat
    /// 500, and baseCost itself already jumps ~12x per station by design) while the Sushi
    /// Bar's first two managers cost a small fraction of that - later stations of the
    /// FIRST venue outcosting early stations of the NEXT one, backwards from "deeper
    /// venues cost more". The fractional-power formula must keep growth well under the
    /// old flat multiplier's 12x-per-station compounding.
    func testManagerCostScalingIsTamedWithinAVenue() {
        let stations = Balance.venue(0).stations
        XCTAssertLessThan(Balance.managerCost(spec: stations[5]), 100_000_000,
                          "the last Burger Shack station used to cost ~622M to staff")
        for i in 2..<stations.count {
            let ratio = Balance.managerCost(spec: stations[i])
                / Balance.managerCost(spec: stations[i - 1])
            XCTAssertLessThan(ratio, 8,
                              "station-to-station growth should be well under the old flat factor's 12x")
        }
    }

    @MainActor
    func testFirstManagerIsAffordableToANewPlayer() {
        // Automation is the idea the game most needs to teach early, so the opening hire
        // must be reachable rather than a wall at minute one.
        let first = Balance.venue(0).stations[0]
        let second = Balance.venue(0).stations[1]
        XCTAssertLessThan(Balance.managerCost(spec: first), 300)
        XCTAssertEqual(Balance.managerCost(spec: second),
                       Balance.managerCostScale * pow(second.baseCost, Balance.managerCostExponent),
                       "only the first station of a venue is discounted")

        // Reachable from the day-one daily plus a short spell of tapping.
        let e = engine()
        e.addCoins(DailyRewards.minimumCoins(day: 1) + 150)
        XCTAssertTrue(e.hireManager(for: 0))
    }

    @MainActor
    func testTutorialAdvancesOnlyByDoingTheAskedStep() {
        let e = engine()
        XCTAssertEqual(e.state.tutorial.current, .tapStation)

        // Buying first must not skip the tap step.
        e.addCoins(1_000)
        e.buy(station: 0)
        XCTAssertEqual(e.state.tutorial.current, .tapStation)

        e.tap(station: 0)
        XCTAssertEqual(e.state.tutorial.current, .buyLevel)
        e.buy(station: 0)
        XCTAssertEqual(e.state.tutorial.current, .hireManager)
        // A new save locks Coffee Break out for its first 15 minutes, so hireManager skips
        // straight past that tutorial step rather than instructing the player to tap
        // something visibly disabled.
        e.hireManager(for: 0)
        XCTAssertEqual(e.state.tutorial.current, .openGoals)
        e.completeTutorialStep(.openGoals)
        XCTAssertNil(e.state.tutorial.current)
        XCTAssertTrue(e.state.tutorial.finished)
    }

    @MainActor
    func testTutorialSurvivesHiringTheFreeManagerBeforeTappingOrBuying() {
        // The free first-station hire has no prerequisite - a player can claim it as their
        // very first action, before the tutorial has even asked them to tap or buy anything.
        // Reported live TWICE now: the first report was hiring then never revisiting the hire
        // step (fixed by skipping hireManager/coffeeBreak from buy()); the second was hiring
        // as the literal first action and never tapping or buying at all, which that first fix
        // never covered - the overlay stayed on "Cook something," pointing at a station that
        // was now staffed and auto-running, and tapping an already-staffed station is a no-op
        // the player has no reason to ever attempt.
        let e = engine()
        XCTAssertEqual(e.state.tutorial.current, .tapStation)

        // The free-hire button (StationListView) passes free: true explicitly when
        // eligibleForFreeFirstManager is true; hireManager itself doesn't infer it.
        XCTAssertTrue(e.hireManager(for: 0, free: true))
        XCTAssertTrue(e.state.freeFirstManagerClaimed)
        // Staffed before ever being tapped or bought - tapStation, buyLevel, and hireManager
        // are all moot now, and a new save locks Coffee Break out for its first 15 minutes, so
        // the whole chain skips straight to the first step actually actionable.
        XCTAssertEqual(e.state.tutorial.current, .openGoals,
                       "hiring before tapping or buying must skip every step it makes moot")
    }

    @MainActor
    func testTutorialSkipsOnlyThroughHireManagerWhenCoffeeBreakIsAlreadyReady() {
        // Same bare hire-first scenario, but with the coffee break lock already past - the
        // skip chain inside hireManager() must stop at coffeeBreak, not run past it too.
        let e = engine()
        e.debugAdvanceClock(seconds: 20 * 60) // clear the new-save Coffee Break lock
        XCTAssertTrue(e.boostReady)

        XCTAssertTrue(e.hireManager(for: 0, free: true))
        XCTAssertEqual(e.state.tutorial.current, .coffeeBreak)
    }

    @MainActor
    func testTutorialShowsCoffeeBreakStepWhenTheBoostIsActuallyReady() {
        // The skip in hireManager() is specifically about the boost not being ready - if it
        // is (e.g. an old save, or the 15-minute gate has already passed), the step should
        // still show and only complete once the player actually claims it.
        var state = GameState.newGame()
        state.boostAvailableAt = .distantPast
        let e = engine(state)
        e.addCoins(1_000)

        e.tap(station: 0)
        e.buy(station: 0)
        e.hireManager(for: 0)
        XCTAssertEqual(e.state.tutorial.current, .coffeeBreak)

        XCTAssertTrue(e.claimFreeBoost())
        XCTAssertEqual(e.state.tutorial.current, .openGoals)
    }

    func testTutorialIsSkippedForASaveWithHistory() {
        var state = GameState.newGame()
        state.lifetimeEarnings = 50_000
        state.reconcileWithCatalog()
        XCTAssertTrue(state.tutorial.finished, "an existing player is not a new player")

        var fresh = GameState.newGame()
        fresh.reconcileWithCatalog()
        XCTAssertFalse(fresh.tutorial.finished)
    }

    // MARK: New gem sinks (Automate Venue, Chef's Reserve)

    @MainActor
    func testAutomateVenueStaffsEverythingAtOnce() {
        var state = GameState.newGame()
        state.gems = 1000
        state.venues[0].stations[0].level = 5
        state.venues[0].stations[1].level = 5
        state.venues[0].stations[2].level = 5
        let e = engine(state)
        let offer = GemOffer.all.first { $0.id == "automate" }!

        let before = e.state.gems
        guard case .success = GemSpend.redeem(offer, engine: e) else {
            return XCTFail("expected the sink to succeed with open stations to staff")
        }
        XCTAssertEqual(e.state.gems, before - offer.cost)
        XCTAssertTrue(e.state.venues[0].stations[0].isStaffed)
        XCTAssertTrue(e.state.venues[0].stations[1].isStaffed)
        XCTAssertTrue(e.state.venues[0].stations[2].isStaffed)
    }

    @MainActor
    func testAutomateVenueRefusesWhenNothingToDo() {
        var state = GameState.newGame()
        // Staff the only owned station directly (free), so there is nothing left to automate.
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)
        e.addGems(1000)
        let offer = GemOffer.all.first { $0.id == "automate" }!
        let before = e.state.gems

        guard case .nothingToDo = GemSpend.redeem(offer, engine: e) else {
            return XCTFail("a fully staffed venue must refuse rather than charge for nothing")
        }
        XCTAssertEqual(e.state.gems, before, "a refused purchase must not spend gems")
    }

    @MainActor
    func testAutomateVenueRefusesWithoutEnoughGems() {
        var state = GameState.newGame()
        state.venues[0].stations[1].level = 5
        let e = engine(state)
        XCTAssertEqual(GemSpend.redeem(GemOffer.all.first { $0.id == "automate" }!, engine: e),
                       .insufficientGems)
    }

    @MainActor
    func testChefsReserveGrantsATripleProfitBoost() {
        let e = engine()
        e.addGems(1000)
        let offer = GemOffer.all.first { $0.id == "reserve" }!

        guard case .success = GemSpend.redeem(offer, engine: e) else {
            return XCTFail("expected the boost purchase to succeed")
        }
        let boost = e.state.activeBoosts.first { $0.id == "chefs-reserve" }
        XCTAssertEqual(boost?.multiplier, 3)
        XCTAssertEqual(boost?.remaining(at: e.state.now) ?? 0, 3*3600, accuracy: 2)
    }

    // MARK: New whale IAPs

    func testWhaleCatalogIsPricedAsAnIncreasingCurve() {
        // Every tier should offer a better gems-per-dollar rate than the one before it -
        // otherwise a bigger spend is a worse deal, which defeats the point of a whale ladder.
        func gemsPerDollar(_ item: ShopItem) -> Double? {
            guard case .gems(let amount) = item.reward,
                  let price = Double(item.fallbackPrice.trimmingCharacters(in: CharacterSet(charactersIn: "$")))
            else { return nil }
            return Double(amount) / price
        }
        let rates = ShopCatalog.gemPacks.compactMap(gemsPerDollar)
        XCTAssertEqual(rates.count, ShopCatalog.gemPacks.count, "every gem pack must price cleanly")
        for (a, b) in zip(rates, rates.dropFirst()) {
            XCTAssertLessThan(a, b, "each bigger gem pack should beat the smaller one's rate")
        }
    }

    @MainActor
    func testLegendaryChefCrateGrantsAGuaranteedLegendary() {
        let e = engine()
        let store = StoreService(engine: e)
        let item = ShopCatalog.offers.first { $0.reward == .legendaryManager }!

        XCTAssertTrue(e.state.managers.isEmpty)
        // grant() is private; exercise it the way a real purchase would via the public
        // engine call it wraps, matching what StoreService.grant(_:announce:) does internally.
        let spec = e.grantManager(rarity: .legendary)
        XCTAssertEqual(spec.rarity, .legendary)
        XCTAssertEqual(e.state.managers.count, 1)
        XCTAssertEqual(e.state.managers.first?.specID, spec.id)
        XCTAssertFalse(store.isOwned(item), "a repeatable consumable never reads as permanently owned")
    }

    @MainActor
    func testFranchiseAcceleratorGrantsAllThreeRewards() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        let gemsBefore = e.state.gems
        let coinsBefore = e.state.coins
        let expectedCoins = e.state.automatedRate * 8 * 3600

        let earned = e.grantFranchiseAccelerator()

        XCTAssertEqual(e.state.gems, gemsBefore + 2_500)
        XCTAssertEqual(earned, expectedCoins, accuracy: max(1, expectedCoins * 1e-9))
        XCTAssertEqual(e.state.coins, coinsBefore + expectedCoins, accuracy: max(1, expectedCoins * 1e-9))
        XCTAssertEqual(e.state.activeBoosts.first { $0.id == "accelerator" }?.multiplier, 2)
    }

    func testNewIAPsAreAllRepeatableConsumables() {
        for id: ShopReward in [.legendaryManager, .accelerator] {
            let item = ShopCatalog.all.first { $0.reward == id }
            XCTAssertNotNil(item, "\(id) must be in the catalog")
            XCTAssertTrue(item?.isConsumable ?? false, "\(id) must be repeatable, not one-time")
        }
    }

    // MARK: Shop sort order

    func testGemSinksDisplayCheapestFirst() {
        let sorted = GemOffer.allSortedByCost
        XCTAssertEqual(sorted.count, GemOffer.all.count, "sorting must not drop or duplicate an offer")
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThanOrEqual(a.cost, b.cost)
        }
        XCTAssertEqual(sorted.first?.id, "instant", "Serve Everyone at 20 gems is the cheapest sink")
    }

    // MARK: Festival ticket gem sink

    @MainActor
    func testTicketBundlePaysOutRegardlessOfTheServeCap() {
        // Serve-sourced tickets are capped at 45% of the track (tested elsewhere); a
        // purchased top-up is a different source entirely and must not be throttled by it.
        var state = GameState.newGame()
        state.gems = 1000
        state.festival.ticketsFromServing = Festival.maxTicketsFromServing  // already maxed out
        let e = engine(state)
        let offer = GemOffer.all.first { $0.id == "tickets" }!

        let before = e.state.festival.tickets
        guard case .success = GemSpend.redeem(offer, engine: e) else {
            return XCTFail("a ticket purchase must succeed even with the serve cap maxed")
        }
        XCTAssertEqual(e.state.festival.tickets, before + 500)
    }

    @MainActor
    func testTicketBundleRefusesWithoutEnoughGems() {
        let e = engine()
        XCTAssertEqual(GemSpend.redeem(GemOffer.all.first { $0.id == "tickets" }!, engine: e),
                       .insufficientGems)
    }

    // MARK: Grand Opening Bundle

    @MainActor
    func testGrandOpeningBundleAutomatesEveryUnlockedVenueNotJustOne() {
        var state = GameState.newGame()
        state.venues[1].unlocked = true
        state.venues[1].stations[0].level = 3
        state.venues[1].stations[2].level = 3
        let e = engine(state)
        let before = e.state.gems

        e.grantGrandOpeningBundle()

        XCTAssertTrue(e.state.venues[0].stations[0].isStaffed, "venue 0's starting station")
        XCTAssertTrue(e.state.venues[1].stations[0].isStaffed)
        XCTAssertTrue(e.state.venues[1].stations[2].isStaffed)
        XCTAssertEqual(e.state.gems, before + 1_500)
        XCTAssertEqual(e.state.activeBoosts.first { $0.id == "grand-opening" }?.multiplier, 2)
    }

    @MainActor
    func testGrandOpeningBundleGrantsExactlyOnceAcrossRepeatedEntitlementRefreshes() {
        // A non-consumable is re-delivered by StoreKit's currentEntitlements on every launch.
        // The engine call itself is idempotent-unsafe by design (it always grants) - the
        // one-time guard belongs to the caller, which is what this exercises: the same
        // firstTime-check pattern already proven for the Starter Pack.
        let e = engine()
        XCTAssertFalse(e.state.entitlements.grandOpeningBundle)
        let before = e.state.gems

        let firstTime = !e.state.entitlements.grandOpeningBundle
        e.setEntitlement(grandOpeningBundle: true)
        if firstTime { e.grantGrandOpeningBundle() }
        XCTAssertEqual(e.state.gems, before + 1_500)

        // Simulate the exact same call landing again on a later launch.
        let secondTime = !e.state.entitlements.grandOpeningBundle
        e.setEntitlement(grandOpeningBundle: true)
        if secondTime { e.grantGrandOpeningBundle() }
        XCTAssertEqual(e.state.gems, before + 1_500, "must not double-grant on a repeated entitlement refresh")
    }

    // MARK: Entitlements save-compatibility

    func testEntitlementsDecodeFineWithoutTheNewestField() throws {
        // The exact trap that already bit GameState once this session: adding a new
        // non-optional stored property to a Codable struct makes the synthesized decoder
        // throw on ANY save that predates the field - not just default it to false. Confirms
        // Entitlements' hand-written decoder actually guards against that.
        let legacyJSON = """
        {"vip": true, "starterPack": false}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Entitlements.self, from: legacyJSON)
        XCTAssertTrue(decoded.vip)
        XCTAssertFalse(decoded.starterPack)
        XCTAssertFalse(decoded.grandOpeningBundle, "a missing key must default, not throw")
    }

    func testEntitlementsRoundTripsAllThreeFlags() throws {
        var e = Entitlements()
        e.vip = true
        e.grandOpeningBundle = true
        let data = try JSONEncoder().encode(e)
        let restored = try JSONDecoder().decode(Entitlements.self, from: data)
        XCTAssertEqual(restored, e)
    }

    // MARK: League - the one free route to Legendary rarity

    @MainActor
    func testToppingDiamondGrantsAFreeLegendaryManager() {
        var state = GameState.newGame()
        state.league = League.newWeek(tier: .diamond, now: Date(), seasonsPlayed: 0)
        state.league.endsAt = Date().addingTimeInterval(-1)
        state.league.rivals.indices.forEach { state.league.rivals[$0].score = 0 }
        state.league.score = 1  // beats every zeroed rival -> rank 1

        let e = engine(state)
        XCTAssertTrue(e.state.managers.isEmpty)
        e.settleLeagueIfFinished()

        XCTAssertEqual(e.state.managers.count, 1, "rank 1 in Diamond is the one free path to Legendary")
        XCTAssertEqual(e.state.managers.first?.spec.rarity, .legendary)
    }

    @MainActor
    func testFinishingSecondInDiamondGrantsNoManager() {
        var state = GameState.newGame()
        state.league = League.newWeek(tier: .diamond, now: Date(), seasonsPlayed: 0)
        state.league.endsAt = Date().addingTimeInterval(-1)
        state.league.rivals.indices.forEach { state.league.rivals[$0].score = 0 }
        state.league.rivals[0].score = 1_000_000  // one rival stays ahead -> player rank 2
        state.league.score = 1

        let e = engine(state)
        e.settleLeagueIfFinished()

        XCTAssertTrue(e.state.managers.isEmpty, "only rank 1 specifically grants the free legendary")
    }

    // MARK: Prestige interaction

    @MainActor
    func testFranchiseResetKeepsTheCollectionsButClearsTheBoard() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 60
        state.venues[0].stations[0].perks = [25: 0]
        // A coin-hired manager - gets let go, same as the tutorial-free trainee would.
        state.hire(specID: "dex", venue: 0, station: 0)
        // A gem-bought manager on the same venue - survives, same as an IAP/reward grant would.
        state.hire(specID: "vera", venue: 0, station: 1, premium: true)
        state.recipeCards[Recipes.key(venue: 0, station: 0)] = 2
        state.research["prep"] = 3
        state.venues[1].unlocked = true

        let e = engine(state)
        e.addCoins(Balance.minimumLifetimeForPrestige * 4)
        e.debugUnlockAllVenuesAndStations()
        let awarded = e.prestige()
        XCTAssertGreaterThan(awarded, 0)

        // Kept: the things the player collected, minus any staff paid for in plain coins.
        XCTAssertEqual(e.state.managers.count, 1, "only the premium (gem-bought) manager survives")
        XCTAssertEqual(e.state.managers.first?.specID, "vera")
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

        // The surviving manager is unassigned rather than deleted, so it can go straight back
        // to work - the coin-hired one is gone entirely, not just benched.
        XCTAssertEqual(e.state.unassignedManagers.count, 1)
        XCTAssertEqual(e.state.assignedManagerCount, 0)
    }

    @MainActor
    func testStaleBoardCostsMoreAndFranchisingResetsTheStalenessPortion() {
        let e = engine()
        XCTAssertEqual(e.costInflation, 1, accuracy: 1e-9, "a brand new board isn't taxed yet")

        // Elapsed time alone must NOT tax an incomplete board: a calibration run against the
        // real venue-unlock curve found venue 5 never unlocking inside 150 simulated hours of
        // maximally-engaged play, because this same tax was compounding the whole time - a
        // player working as fast as possible toward the (now mandatory) full-buildout gate was
        // being taxed for not having already passed it. See staleCostInflation's doc comment.
        e.debugSkip(hours: Balance.staleGraceHours + 24 * 3)
        XCTAssertEqual(e.costInflation, 1, accuracy: 1e-9,
                       "an incomplete board is never stale, no matter how much time passes")

        // Only once the board is actually fully built out does the tax apply - matching
        // canPrestige's own gate, since that's the moment a player could act and is choosing
        // not to. Board age was already skipped past grace above, so buildout and staleness
        // land in the same instant here - price(for:) is compared against Balance's own raw,
        // uninflated cost rather than a "fresh" price captured before this point, since no
        // such moment exists once time has already been fast-forwarded.
        e.debugUnlockAllVenuesAndStations()
        let rawPrice = Balance.cost(spec: Balance.venue(0).stations[0],
                                    level: e.state.venues[0].stations[0].level,
                                    quantity: e.quantity(for: 0))
        XCTAssertGreaterThan(e.costInflation, 1, "a fully built, stale board should cost more")
        XCTAssertEqual(e.price(for: 0), rawPrice * e.costInflation, accuracy: rawPrice * e.costInflation * 0.01,
                       "the station price scales with the same inflation factor")
        XCTAssertGreaterThan(e.managerCost(for: 0), Balance.managerCost(spec: Balance.venue(0).stations[0]),
                             "manager hire cost is taxed too")
        XCTAssertGreaterThan(e.unlockCost(for: Balance.venue(1)), Balance.venue(1).unlockCost,
                             "venue unlock cost is taxed too, so it can't dodge the tax")

        e.addCoins(Balance.minimumLifetimeForPrestige * 4)
        _ = e.prestige()
        XCTAssertEqual(e.staleCostInflation, 1, accuracy: 1e-9, "franchising starts a fresh, untaxed board")
        XCTAssertEqual(e.costInflation, Balance.starMultiplier(stars: e.state.lifetimeStars), accuracy: 1e-6,
                       "but costInflation itself carries the player's own star multiplier - the whole " +
                       "point is that a reset can't zero out a permanent bonus, only the staleness part")
    }

    /// Live report: a second prestige landed minutes after the first (100B lifetime earnings
    /// to reach prestige 1, ~2.56 quintillion for the next - both inside the same short
    /// session). Root cause: post-prestige boards charged first-timer prices while paying out
    /// at the player's permanent, star-boosted rate. costInflation now carries the same star
    /// multiplier automatedRate does, so the two cancel out in the pace math and a
    /// star-boosted player doesn't out-race their own costs.
    @MainActor
    func testCostsScaleWithTheStarMultiplierSoARunawayCannotStartOver() {
        var state = GameState.newGame()
        state.lifetimeStars = 270_000 // roughly the 7000%-bonus report
        state.venues[0].stations[0].level = 50
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        let boosted = e.costInflation
        XCTAssertEqual(boosted, Balance.starMultiplier(stars: 270_000), accuracy: 1e-6)
        XCTAssertGreaterThan(boosted, 60, "a real prestige-scale star count should tax costs by many multiples")

        // The pace test that actually matters: automatedRate carries the same multiplier
        // costInflation now does, so the ratio (what governs "how long until I can afford
        // the next thing") is unchanged by how many stars the player has.
        let boostedRatio = e.unlockCost(for: Balance.venue(1)) / max(e.state.automatedRate, 1)

        var zero = GameState.newGame()
        zero.venues[0].stations[0].level = 50
        zero.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let zeroEngine = GameEngine(state: zero, startTimers: false, persistence: EphemeralPersistence())
        let zeroRatio = zeroEngine.unlockCost(for: Balance.venue(1)) / max(zeroEngine.state.automatedRate, 1)

        XCTAssertEqual(boostedRatio, zeroRatio, accuracy: zeroRatio * 0.01,
                       "cost/rate - the thing that actually determines how long a purchase takes - " +
                       "should land in the same place regardless of the player's star multiplier")
    }

    // MARK: Cloud sync

    func testCloudPicksTheSaveThatHasSeenMoreOfTheGame() {
        // Lifetime earnings only ever go up, so it beats a timestamp - a device with a wrong
        // clock could otherwise win with nothing to show for it.
        var a = GameState.newGame(); a.lifetimeEarnings = 5_000
        var b = GameState.newGame(); b.lifetimeEarnings = 9_000
        XCTAssertTrue(CloudSaveService.isAhead(b, of: a))
        XCTAssertFalse(CloudSaveService.isAhead(a, of: b))

        // Stars outrank earnings: a franchised save is further along even after its reset.
        var franchised = GameState.newGame()
        franchised.lifetimeStars = 200
        franchised.lifetimeEarnings = 1_000
        var grinding = GameState.newGame()
        grinding.lifetimeEarnings = 500_000
        XCTAssertTrue(CloudSaveService.isAhead(franchised, of: grinding))
    }

    func testIdenticalSavesAreNotConsideredAhead() {
        let a = GameState.newGame()
        XCTAssertFalse(CloudSaveService.isAhead(a, of: a))
    }

    @MainActor
    func testAdoptingACloudSaveReplacesLocalProgressWholesale() {
        var remote = GameState.newGame()
        remote.lifetimeEarnings = 9_000_000
        remote.lifetimeStars = 40
        remote.gems = 777
        remote.venues[0].stations[0].level = 88

        let e = engine()
        e.addCoins(10)
        e.adoptCloudSave(remote)

        XCTAssertEqual(e.state.gems, 777)
        XCTAssertEqual(e.state.lifetimeStars, 40)
        XCTAssertEqual(e.state.venues[0].stations[0].level, 88)
        // The adopted save still gets its quest slots and league seeded.
        XCTAssertEqual(e.state.quests.count, Quests.slots)
        XCTAssertFalse(e.state.league.rivals.isEmpty)
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

    // MARK: 11 - Achievements

    func testAchievementCatalogHasUniqueIDs() {
        let ids = AchievementCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    @MainActor
    func testAchievementIsNotClaimableBelowThreshold() {
        let e = engine()
        XCTAssertFalse(Achievements.isComplete(AchievementCatalog.spec("serve_1")!, state: e.state))
        XCTAssertNil(e.claimAchievement(id: "serve_1"))
        XCTAssertTrue(e.claimableAchievements.isEmpty)
    }

    @MainActor
    func testAchievementClaimsOncePastThresholdAndPaysGems() {
        var state = GameState.newGame()
        state.totalServed = 10_000
        let e = engine(state)
        XCTAssertTrue(e.claimableAchievements.contains { $0.id == "serve_1" })

        let before = e.state.gems
        let claimed = e.claimAchievement(id: "serve_1")
        XCTAssertEqual(claimed?.id, "serve_1")
        XCTAssertEqual(e.state.gems, before + 15)
        XCTAssertTrue(e.state.claimedAchievements.contains("serve_1"))

        // Claiming again pays nothing a second time.
        XCTAssertNil(e.claimAchievement(id: "serve_1"))
        XCTAssertEqual(e.state.gems, before + 15)
        XCTAssertFalse(e.claimableAchievements.contains { $0.id == "serve_1" })
    }

    /// The "Claim All" button on the Achievements tab - sweeps every claimable achievement
    /// in one tap.
    @MainActor
    func testClaimAllAchievementsClaimsEveryCompleteOneAtOnce() {
        var state = GameState.newGame()
        state.totalServed = 10_000
        state.totalTaps = 1_000
        let e = engine(state)
        XCTAssertEqual(Set(e.claimableAchievements.map(\.id)), ["serve_1", "tap_1"])

        let before = e.state.gems
        XCTAssertEqual(e.claimAllAchievements(), 2)
        XCTAssertEqual(e.state.gems, before + 15 + 15)
        XCTAssertTrue(e.state.claimedAchievements.isSuperset(of: ["serve_1", "tap_1"]))
        XCTAssertEqual(e.claimAllAchievements(), 0, "nothing left to claim")
    }

    @MainActor
    func testPrestigeCountDrivesThePrestigeAchievements() {
        var state = GameState.newGame()
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        let e = engine(state)
        e.debugUnlockAllVenuesAndStations()
        XCTAssertTrue(e.canPrestige, "the seeded lifetime earnings must clear the prestige gate")
        XCTAssertEqual(e.state.prestigeCount, 0)
        e.prestige()
        XCTAssertEqual(e.state.prestigeCount, 1)
        XCTAssertTrue(Achievements.isComplete(AchievementCatalog.spec("prestige_1")!, state: e.state))
    }

    @MainActor
    func testBestLeagueTierReachedOnlyEverIncreases() {
        var state = GameState.newGame()
        state.league = League.newWeek(tier: .gold, now: Date(), seasonsPlayed: 3)
        state.bestLeagueTierReached = .gold
        state.league.endsAt = Date().addingTimeInterval(-1) // force it finished
        state.league.score = -1 // guarantee last place so the outcome is a relegation
        let e = engine(state)

        e.settleLeagueIfFinished()

        // Relegated out of Gold, but the best-ever tier must not regress.
        XCTAssertEqual(e.state.bestLeagueTierReached, .gold)
    }

    func testAchievementFractionClampsAtOne() {
        var state = GameState.newGame()
        state.totalServed = 999_999_999
        let spec = AchievementCatalog.spec("serve_1")!
        XCTAssertEqual(Achievements.fraction(spec, state: state), 1)
    }

    // MARK: 12 - Login streak

    func testFirstClaimStartsStreakAtOne() {
        var state = GameState.newGame()
        _ = DailyRewards.claim(state: &state, now: Date())
        XCTAssertEqual(state.daily.streakLength, 1)
    }

    func testConsecutiveDayClaimIncrementsStreak() {
        var state = GameState.newGame()
        let day1 = Date()
        _ = DailyRewards.claim(state: &state, now: day1)
        let day2 = Calendar.current.date(byAdding: .day, value: 1, to: day1)!
        _ = DailyRewards.claim(state: &state, now: day2)
        XCTAssertEqual(state.daily.streakLength, 2)
    }

    func testMissedDayWithoutFreezeResetsStreak() {
        var state = GameState.newGame()
        let day1 = Date()
        _ = DailyRewards.claim(state: &state, now: day1)
        let day3 = Calendar.current.date(byAdding: .day, value: 2, to: day1)! // day 2 skipped
        _ = DailyRewards.claim(state: &state, now: day3)
        XCTAssertEqual(state.daily.streakLength, 1)
    }

    func testMissedDayWithFreezeConsumesItAndPreservesStreak() {
        var state = GameState.newGame()
        state.daily.streakFreezes = 1
        let day1 = Date()
        _ = DailyRewards.claim(state: &state, now: day1)
        let day3 = Calendar.current.date(byAdding: .day, value: 2, to: day1)!
        _ = DailyRewards.claim(state: &state, now: day3)
        XCTAssertEqual(state.daily.streakLength, 2, "the freeze should absorb the missed day")
        XCTAssertEqual(state.daily.streakFreezes, 0, "and be consumed in the process")
    }

    @MainActor
    func testStreakMilestoneClaimsOncePastLength() {
        var state = GameState.newGame()
        state.daily.streakLength = 7
        let e = engine(state)
        XCTAssertTrue(e.claimableStreakMilestones.contains { $0.day == 7 })

        let before = e.state.gems
        let gems = e.claimStreakMilestone(day: 7)
        XCTAssertEqual(gems, 32)
        XCTAssertEqual(e.state.gems, before + 32)

        XCTAssertNil(e.claimStreakMilestone(day: 7))
        XCTAssertEqual(e.state.gems, before + 32)
        XCTAssertFalse(e.claimableStreakMilestones.contains { $0.day == 7 })
    }

    @MainActor
    func testStreakFreezeGemSinkAddsAFreeze() {
        var state = GameState.newGame()
        state.gems = 1000
        let e = engine(state)
        let offer = GemOffer.all.first { $0.id == "freeze" }!
        guard case .success = GemSpend.redeem(offer, engine: e) else {
            return XCTFail("a streak freeze purchase should succeed with enough gems")
        }
        XCTAssertEqual(e.state.daily.streakFreezes, 1)
    }

    func testDailyRewardStateDecodesFineWithoutStreakFields() throws {
        let legacyJSON = """
        {"currentDay": 3, "lastClaimedDay": null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DailyRewardState.self, from: legacyJSON)
        XCTAssertEqual(decoded.currentDay, 3)
        XCTAssertEqual(decoded.streakLength, 0)
        XCTAssertEqual(decoded.streakFreezes, 0)
        XCTAssertTrue(decoded.claimedStreakMilestones.isEmpty)
    }

    // MARK: 13 - Manager errands

    @MainActor
    func testStartingAnErrandBenchesTheManager() {
        var state = GameState.newGame()
        let manager = OwnedManager.make("dex")
        state.managers.append(manager)
        let e = engine(state)
        XCTAssertTrue(e.state.unassignedManagers.contains { $0.id == manager.id })

        XCTAssertTrue(e.startErrand(managerID: manager.id, hours: 2))

        XCTAssertFalse(e.state.unassignedManagers.contains { $0.id == manager.id },
                       "an erranded manager must not be assignable to a station")
        XCTAssertEqual(e.state.errands.count, 1)
    }

    @MainActor
    func testCannotDoubleBookTheSameManagerOnAnErrand() {
        var state = GameState.newGame()
        let manager = OwnedManager.make("dex")
        state.managers.append(manager)
        let e = engine(state)

        XCTAssertTrue(e.startErrand(managerID: manager.id, hours: 2))
        XCTAssertFalse(e.startErrand(managerID: manager.id, hours: 2),
                       "the same manager can't be sent on a second errand while already away")
        XCTAssertEqual(e.state.errands.count, 1)
    }

    @MainActor
    func testErrandSlotsAreCapped() {
        var state = GameState.newGame()
        let managers = (0..<(Errands.maxSlots + 1)).map { _ in OwnedManager.make("dex") }
        state.managers.append(contentsOf: managers)
        let e = engine(state)

        for manager in managers {
            _ = e.startErrand(managerID: manager.id, hours: 2)
        }

        XCTAssertEqual(e.state.errands.count, Errands.maxSlots)
    }

    @MainActor
    func testCannotCollectAnErrandBeforeItsDurationElapses() {
        var state = GameState.newGame()
        let manager = OwnedManager.make("dex")
        state.managers.append(manager)
        let e = engine(state)
        e.startErrand(managerID: manager.id, hours: 6)
        let id = e.state.errands[0].id

        XCTAssertNil(e.collectErrand(id: id))
        XCTAssertEqual(e.state.errands.count, 1)
    }

    @MainActor
    func testCollectingAnErrandPaysOutOnceAndFreesTheManager() {
        var state = GameState.newGame()
        let manager = OwnedManager.make("dex")
        state.managers.append(manager)
        let e = engine(state)
        e.startErrand(managerID: manager.id, hours: 2)
        let id = e.state.errands[0].id
        let gemsBefore = e.state.gems

        e.debugSkip(hours: 2)

        let claimed = e.collectErrand(id: id)
        XCTAssertNotNil(claimed)
        XCTAssertEqual(e.state.gems, gemsBefore + (claimed?.rewardGems ?? -1))
        XCTAssertTrue(e.state.errands.isEmpty)
        XCTAssertTrue(e.state.unassignedManagers.contains { $0.id == manager.id },
                     "the manager must return to the bench once the errand is collected")

        // Collecting the same id again does nothing - it's already gone.
        XCTAssertNil(e.collectErrand(id: id))
    }

    /// The "Claim All" button on the Errands tab - only collects errands that are actually
    /// done, leaves the rest running.
    @MainActor
    func testClaimAllErrandsCollectsOnlyTheOnesThatFinished() {
        var state = GameState.newGame()
        let managers = (0..<2).map { _ in OwnedManager.make("dex") }
        state.managers.append(contentsOf: managers)
        let e = engine(state)

        e.startErrand(managerID: managers[0].id, hours: 2)
        e.startErrand(managerID: managers[1].id, hours: 10) // still running

        e.debugSkip(hours: 2)

        XCTAssertEqual(e.claimAllErrands(), 1)
        XCTAssertEqual(e.state.errands.count, 1, "the 10h errand must still be running")
        XCTAssertEqual(e.claimAllErrands(), 0, "nothing else ready yet")

        e.debugSkip(hours: 8)
        XCTAssertEqual(e.claimAllErrands(), 1, "the long errand is done now")
        XCTAssertTrue(e.state.errands.isEmpty)
    }

    // MARK: 14 - Customer orders

    @MainActor
    func testStationOrderTargetsAStaffedStationAndPaysOutOnServe() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 40
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        while e.activeOrder == nil { e.rollStationOrder() }
        let order = e.activeOrder!
        XCTAssertEqual(order.venue, 0)
        XCTAssertEqual(order.station, 0)

        let before = e.state.coins
        let cycle = e.state.cycleTime(venue: 0, station: 0)
        e.advance(by: cycle + 0.01)

        XCTAssertNil(e.activeOrder, "fulfilling the order clears it")
        XCTAssertGreaterThan(e.state.coins, before)
    }

    @MainActor
    func testStationOrderExpiresWithoutPayoutIfMissed() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 40
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        while e.activeOrder == nil { e.rollStationOrder() }

        // A big clock skip pushes `now` well past the order's short window; the following
        // tiny advance's own delta is far too small to complete a station cycle, so this
        // can only be exercising the expiry path, not an accidental fulfillment.
        e.debugSkip(hours: 1)
        e.advance(by: 0.01)

        XCTAssertNil(e.activeOrder, "an unmet order should not linger past its window")
    }

    @MainActor
    func testStationOrderNeverTargetsAnUnstaffedStation() {
        // A fresh save owns station 0 but nothing is staffed yet.
        let e = engine()
        for _ in 0..<200 { e.rollStationOrder() }
        XCTAssertNil(e.activeOrder)
    }

    @MainActor
    func testStationOrderDoesNotReplaceItselfWhileActive() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 40
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let e = engine(state)

        while e.activeOrder == nil { e.rollStationOrder() }
        let first = e.activeOrder

        for _ in 0..<50 { e.rollStationOrder() }
        XCTAssertEqual(e.activeOrder, first, "a live order must not be clobbered by later rolls")
    }

    // MARK: 15 - Venue cosmetics

    func testClassicSkinIsAlwaysUnlocked() {
        let state = GameState.newGame()
        XCTAssertTrue(state.hasUnlockedSkin(venue: 0, skin: "classic"))
        XCTAssertEqual(state.skin(venue: 0), "classic", "the default with no purchase yet")
    }

    func testVenuePaletteDiffersBetweenSkins() {
        let classic = VenuePalette.of(.burger, skin: "classic")
        let neon = VenuePalette.of(.burger, skin: "neon")
        XCTAssertNotEqual(classic.counter, neon.counter)
    }

    @MainActor
    func testUnlockingASkinSpendsCoinsOnceAndEquipsIt() {
        let e = engine()
        let price = e.skinPrice(venue: 0)
        e.addCoins(price + 100)
        let before = e.state.coins

        XCTAssertTrue(e.unlockSkin(venue: 0, skin: "neon"))
        XCTAssertEqual(e.state.coins, before - price, accuracy: 1)
        XCTAssertEqual(e.state.skin(venue: 0), "neon")
        XCTAssertTrue(e.state.hasUnlockedSkin(venue: 0, skin: "neon"))

        // A second "unlock" of the same skin is a no-op, not a double charge.
        let afterFirst = e.state.coins
        XCTAssertFalse(e.unlockSkin(venue: 0, skin: "neon"))
        XCTAssertEqual(e.state.coins, afterFirst)
    }

    @MainActor
    func testCannotUnlockASkinWithoutEnoughCoins() {
        let e = engine()
        XCTAssertFalse(e.unlockSkin(venue: 0, skin: "neon"))
        XCTAssertFalse(e.state.hasUnlockedSkin(venue: 0, skin: "neon"))
    }

    @MainActor
    func testReEquippingAnUnlockedSkinIsFree() {
        let e = engine()
        e.addCoins(e.skinPrice(venue: 0) + 100)
        XCTAssertTrue(e.unlockSkin(venue: 0, skin: "neon"))
        XCTAssertTrue(e.setSkin(venue: 0, skin: "classic"))
        XCTAssertEqual(e.state.skin(venue: 0), "classic")

        let before = e.state.coins
        XCTAssertTrue(e.setSkin(venue: 0, skin: "neon"), "already unlocked, so this must not need coins")
        XCTAssertEqual(e.state.coins, before)
        XCTAssertEqual(e.state.skin(venue: 0), "neon")
    }

    // MARK: 16 - Legacy (second prestige layer)

    func testLegacyMultiplierIsReflectedInGlobalMultiplier() {
        var state = GameState.newGame()
        state.legacy.level = 2
        // Isolate the legacy term: zero out every other multiplicative contributor.
        XCTAssertEqual(state.globalMultiplier, Balance.legacyMultiplier(level: 2), accuracy: 0.0001)
        XCTAssertEqual(Balance.legacyMultiplier(level: 2), 1.40, accuracy: 0.0001)
    }

    @MainActor
    func testLegacyResetIsGatedBelowThePrestigeCount() {
        var state = GameState.newGame()
        state.prestigeCount = Balance.legacyUnlockPrestigeCount - 1
        state.lifetimeStars = 1_000_000 // stars alone must never open the gate
        let e = engine(state)
        XCTAssertFalse(e.canLegacyReset)

        let levelBefore = e.state.legacy.level
        XCTAssertEqual(e.legacyReset(), levelBefore, "a gated reset must be a no-op")
        XCTAssertEqual(e.state.legacy.level, levelBefore)
        XCTAssertEqual(e.state.lifetimeStars, 1_000_000, "untouched by the no-op")
    }

    @MainActor
    func testLegacyResetZeroesRunProgressButKeepsCollections() {
        var state = GameState.newGame()
        state.prestigeCount = Balance.legacyUnlockPrestigeCount
        state.lifetimeStars = 15_000
        state.lifetimeEarnings = 1e14
        state.lastPrestigeAward = 12_000
        state.stars = 200
        state.coins = 5_000
        state.runEarnings = 5_000
        state.research["prep"] = 4
        state.managers.append(OwnedManager.make("dex"))
        state.recipeCards[Recipes.key(venue: 0, station: 0)] = 2
        state.claimedAchievements = ["serve_1"]
        let festivalTicketsBefore = state.festival.tickets
        let e = engine(state)
        XCTAssertTrue(e.canLegacyReset)

        let newLevel = e.legacyReset()
        XCTAssertEqual(newLevel, 1)
        XCTAssertEqual(e.state.legacy.level, 1)

        // Run progress, the star multiplier, AND the earnings history got traded away.
        // Earnings must go too: stars are computed from lifetime earnings, so leaving them
        // meant one instant re-prestige restored the entire multiplier for free.
        XCTAssertEqual(e.state.coins, 0)
        XCTAssertEqual(e.state.runEarnings, 0)
        XCTAssertEqual(e.state.lifetimeEarnings, 0)
        XCTAssertEqual(e.state.stars, 0)
        XCTAssertEqual(e.state.lifetimeStars, 0)
        XCTAssertEqual(e.state.lastPrestigeAward, 0, "research prices fall back to the static floor")
        XCTAssertEqual(e.state.research["prep"], 4,
                       "research is permanent knowledge - Legacy never touches it")
        XCTAssertEqual(e.state.venues[0].stations[0].level, 1)
        XCTAssertFalse(e.canPrestige, "the star climb genuinely restarts - no instant re-prestige")
        XCTAssertFalse(e.canLegacyReset,
                       "the gate re-locks: five NEW franchises before the next Legacy")

        // Collections and accomplishments are not run progress - they survive.
        XCTAssertEqual(e.state.managers.count, 1)
        XCTAssertEqual(e.state.recipeCards[Recipes.key(venue: 0, station: 0)], 2)
        XCTAssertTrue(e.state.claimedAchievements.contains("serve_1"))
        XCTAssertEqual(e.state.festival.tickets, festivalTicketsBefore)
    }

    @MainActor
    func testLegacyMultiplierStacksWithRegularPrestigeAfterwards() {
        var state = GameState.newGame()
        state.prestigeCount = Balance.legacyUnlockPrestigeCount
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        let e = engine(state)
        e.legacyReset()
        XCTAssertEqual(e.state.legacy.level, 1)
        XCTAssertEqual(e.state.lifetimeStars, 0, "legacy must not leave stale stars for the next prestige math to trip on")
        XCTAssertFalse(e.canPrestige, "earnings were zeroed - the climb back is the price")

        // Re-earn the minimum the honest way, then a fresh prestige should behave exactly
        // like any other - legacy level is a separate multiplicative term, not folded into
        // lifetimeStars.
        e.addCoins(Balance.minimumLifetimeForPrestige)
        e.debugUnlockAllVenuesAndStations()
        XCTAssertTrue(e.canPrestige)
        let awarded = e.prestige()
        XCTAssertGreaterThan(awarded, 0)
        XCTAssertEqual(e.state.lifetimeStars, awarded)

        let expected = Balance.starMultiplier(stars: awarded) * Balance.legacyMultiplier(level: 1)
        XCTAssertEqual(e.state.globalMultiplier, expected, accuracy: 0.0001)
    }

    func testLegacyStateDecodesFineWithoutFutureFields() throws {
        let legacyJSON = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LegacyState.self, from: legacyJSON)
        XCTAssertEqual(decoded.level, 0)
    }

    // MARK: 17 - Guest Chef

    func testGuestChefPickIsDeterministicForAGivenDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = GuestChef.current(now: date)
        let b = GuestChef.current(now: date)
        XCTAssertEqual(a.id, b.id)
    }

    func testGuestChefChangesFromOneWeekToTheNext() {
        let week1 = Date(timeIntervalSince1970: 1_700_000_000)
        let week2 = week1.addingTimeInterval(7 * 24 * 3600)
        XCTAssertNotEqual(GuestChef.current(now: week1).id, GuestChef.current(now: week2).id)
    }

    func testGuestSpecsAreExcludedFromTheRandomLegendaryPool() {
        for seed in 0..<200 {
            let spec = ManagerCatalog.random(rarity: .legendary, seed: seed)
            XCTAssertFalse(spec.id.hasPrefix("guest-"),
                          "guest chefs must only be obtainable through the weekly purchase")
        }
    }

    @MainActor
    func testPurchasingGuestChefGrantsTheWeeklySpecAndSpendsGems() {
        var state = GameState.newGame()
        state.gems = 1000
        let e = engine(state)
        let expected = e.currentGuestChef
        let before = e.state.gems

        let hired = e.purchaseGuestChef()
        XCTAssertEqual(hired?.id, expected.id)
        XCTAssertEqual(e.state.gems, before - GuestChef.gemPrice)
        XCTAssertTrue(e.state.managers.contains { $0.specID == expected.id })
    }

    @MainActor
    func testCannotPurchaseGuestChefTwiceInTheSameWeek() {
        var state = GameState.newGame()
        state.gems = 1000
        let e = engine(state)
        XCTAssertNotNil(e.purchaseGuestChef())
        XCTAssertTrue(e.guestChefAlreadyPurchasedThisWeek)
        XCTAssertNil(e.purchaseGuestChef(), "already hired this week's chef")
    }

    @MainActor
    func testCannotPurchaseGuestChefWithoutEnoughGems() {
        var state = GameState.newGame()
        state.gems = 0
        let e = engine(state)
        XCTAssertNil(e.purchaseGuestChef())
        XCTAssertFalse(e.guestChefAlreadyPurchasedThisWeek)
    }

    // MARK: 18 - Notification planner

    func testPlanIncludesRushReadyWhenInTheFuture() {
        var state = GameState.newGame()
        let now = Date()
        state.rushAvailableAt = now.addingTimeInterval(600)
        let plan = NotificationPlanner.plan(for: state, now: now)
        XCTAssertTrue(plan.contains { $0.id == "rush-ready" })
    }

    func testPlanExcludesRushReadyWhenAlreadyAvailable() {
        var state = GameState.newGame()
        let now = Date()
        state.rushAvailableAt = now.addingTimeInterval(-600)
        let plan = NotificationPlanner.plan(for: state, now: now)
        XCTAssertFalse(plan.contains { $0.id == "rush-ready" },
                       "no point reminding about something already ready")
    }

    func testPlanExcludesOfflineCapForPlayersWhoEarnNothingOffline() {
        // A fresh save has no staffed stations, so there is nothing to collect - the old
        // behavior scheduled "come collect" anyway, which read as a bug on day one.
        let state = GameState.newGame()
        let plan = NotificationPlanner.plan(for: state, now: Date())
        XCTAssertFalse(plan.contains { $0.id == "offline-cap-full" })
    }

    func testPlanIncludesOfflineCapOnceSomethingIsStaffed() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 5
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let now = Date()
        let plan = NotificationPlanner.plan(for: state, now: now)
        guard let capPlan = plan.first(where: { $0.id == "offline-cap-full" }) else {
            return XCTFail("a staffed board earns offline, so the cap reminder belongs")
        }
        let expected = now.addingTimeInterval(state.offlineCapHours * 3600)
        XCTAssertEqual(capPlan.fireDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        // The game renders currency without a symbol (matches the HUD), so assert the
        // computed amount itself made it into the copy.
        let amount = state.automatedRate * state.offlineCapHours * 3600
            * state.offlineEfficiency * state.offlineManagerBonus
        XCTAssertTrue(capPlan.body.contains(Format.currency(amount)),
                      "the tease should name the concrete amount")
    }

    func testPlanExcludesFestivalEndingWithNoUnclaimedTiers() {
        let state = GameState.newGame() // fresh save: 0 tickets, nothing unlocked
        let plan = NotificationPlanner.plan(for: state, now: Date())
        XCTAssertFalse(plan.contains { $0.id == "festival-ending" })
    }

    func testPlanIncludesFestivalEndingWhenTiersAreUnclaimed() {
        var state = GameState.newGame()
        state.festival.tickets = 500
        state.festival.endsAt = Date().addingTimeInterval(10 * 24 * 3600)
        let plan = NotificationPlanner.plan(for: state, now: Date())
        XCTAssertTrue(plan.contains { $0.id == "festival-ending" })
    }

    func testPlanIncludesLeagueEndingWhenFarEnoughOut() {
        var state = GameState.newGame()
        state.league.endsAt = Date().addingTimeInterval(10 * 24 * 3600)
        let plan = NotificationPlanner.plan(for: state, now: Date())
        XCTAssertTrue(plan.contains { $0.id == "league-ending" })
    }

    func testPlanExcludesLeagueEndingWhenTheTwoHourWindowHasPassed() {
        var state = GameState.newGame()
        state.league.endsAt = Date().addingTimeInterval(3600) // ends in 1h, window needs 2h notice
        let plan = NotificationPlanner.plan(for: state, now: Date())
        XCTAssertFalse(plan.contains { $0.id == "league-ending" })
    }

    func testActiveErrandDecodesFineWithoutNewerFields() throws {
        let legacyJSON = """
        {"managerID": "dex", "startedAt": "2026-01-01T00:00:00Z", "duration": 7200}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ActiveErrand.self, from: legacyJSON)
        XCTAssertEqual(decoded.managerID, "dex")
        XCTAssertEqual(decoded.rewardGems, 0)
        XCTAssertEqual(decoded.rewardCoins, 0)
        XCTAssertFalse(decoded.id.isEmpty)
    }
}
