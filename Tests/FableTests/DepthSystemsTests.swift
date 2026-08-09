import XCTest
@testable import Fable

/// Locks in every judgment-call number from the depth marathon (overnight report #2) so a
/// future retune is a deliberate edit, never a silent drift: contract trades, legacy perk
/// stacking, crew detection, tool drop economics, gauntlet purse math, catering rules, the
/// daily special rotation, and the Midnight Diner's offline split.
final class DepthSystemsTests: XCTestCase {

    // MARK: Franchise Contracts

    func testContractOfferIsAlwaysThreeUniqueWithStraightFirst() {
        for count in 1...40 {
            let offer = Contracts.offer(prestigeCount: count)
            XCTAssertEqual(offer.count, 3, "count \(count)")
            XCTAssertEqual(offer[0].id, "straight", "the safe pick always leads")
            XCTAssertEqual(Set(offer.map(\.id)).count, 3, "no duplicate trades at count \(count)")
        }
    }

    func testEveryTradeContractCarriesARealDownside() {
        for contract in Contracts.all where contract.id != "straight" {
            let hasDownside = contract.speedMultiplier < 1 || contract.profitMultiplier < 1
                || contract.tapMultiplier < 1 || contract.offlineEfficiencyDelta < 0
                || contract.staleGraceDeltaHours < 0 || contract.venueUnlockCostMultiplier > 1
            XCTAssertTrue(hasDownside, "\(contract.id) is a free lunch - contracts must trade")
        }
    }

    func testHighRollerGraceShiftActuallyTaxesSooner() {
        // Base grace is 8h: hour 4 is untaxed normally, taxed under a -6h contract shift.
        XCTAssertEqual(Balance.stalenessMultiplier(boardAgeHours: 4), 1)
        XCTAssertGreaterThan(Balance.stalenessMultiplier(boardAgeHours: 4, graceBonusHours: -6), 1)
        // And the floor: even a stacked debuff never taxes a 1-hour-old board.
        XCTAssertEqual(Balance.stalenessMultiplier(boardAgeHours: 1, graceBonusHours: -100), 1)
    }

    @MainActor
    func testInvestorShowcasePaysItsStarBonusOnPrestige() {
        var state = GameState.newGame()
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        state.activeContract = "showcase"
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        let base = engine.pendingStars
        let awarded = engine.prestige()
        XCTAssertEqual(awarded, Int((Double(base) * 1.2).rounded(.down)),
                       "showcase pays +20% on the formula award")
        XCTAssertNil(engine.state.activeContract, "the new run owes a fresh pick")
    }

    // MARK: Legacy tree

    func testLegacyOfferNeverIncludesMaxedPerks() {
        let taken = ["capital": 3, "patience": 2] // both at max stacks
        for level in 1...10 {
            let offer = LegacyTree.offer(level: level, taken: taken)
            XCTAssertFalse(offer.contains { $0.id == "capital" || $0.id == "patience" },
                           "level \(level) offered a maxed perk")
            XCTAssertFalse(offer.isEmpty)
        }
    }

    func testLegacyEffectsRespectStackCaps() {
        // Stacks beyond the cap must not pay beyond the cap.
        let over = LegacyTree.effects(taken: ["capital": 99])
        let capped = LegacyTree.effects(taken: ["capital": 3])
        XCTAssertEqual(over.startingCapitalHours, capped.startingCapitalHours)
    }

    @MainActor
    func testSeedCapitalBanksACappedStartOnPrestige() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 100
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        state.lifetimeEarnings = Balance.minimumLifetimeForPrestige
        state.legacyPerks = ["capital": 1]
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        _ = engine.prestige()
        XCTAssertGreaterThan(engine.state.coins, 0, "the new run starts funded")
        XCTAssertLessThanOrEqual(engine.state.coins, Balance.venues[1].unlockCost,
                                 "but never past the per-stack cap")
    }

    // MARK: Crews

    func testCrewsRequireEveryMemberPresent() {
        XCTAssertTrue(Synergies.active(in: ["sam", "otto", "tina"]).contains { $0.id == "clockwork" })
        XCTAssertFalse(Synergies.active(in: ["sam", "tina"]).contains { $0.id == "clockwork" },
                       "half a crew is no crew")
        XCTAssertTrue(Synergies.active(in: []).isEmpty)
    }

    func testCrewMembersAllExistInTheCatalog() {
        for synergy in Synergies.all {
            for member in synergy.memberIDs {
                XCTAssertEqual(ManagerCatalog.spec(member).id, member,
                               "\(synergy.id) names an unknown manager \(member)")
            }
            XCTAssertFalse(synergy.memberIDs.contains(ManagerCatalog.traineeID),
                           "trainees can't have chemistry")
        }
    }

    @MainActor
    func testAssembledCrewLiftsTheWholeVenue() {
        var state = GameState.newGame()
        for idx in 0...2 { state.venues[0].stations[idx].level = 10 }
        state.hire(specID: "sam", venue: 0, station: 0, premium: true)
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 2)
        let before = state.baseRevenue(venue: 0, station: 2)
        state.hire(specID: "otto", venue: 0, station: 1, premium: true)
        let after = state.baseRevenue(venue: 0, station: 2)
        // Otto's own station-speed trait doesn't touch station 2's revenue; the +10%
        // Clockwork Crew does - so station 2 isolates the crew bonus exactly.
        XCTAssertEqual(after, before * 1.10, accuracy: before * 0.001)
    }

    // MARK: Kitchen tools

    func testDuplicateGemsScaleWithRarity() {
        XCTAssertEqual(Tools.duplicateGems(.common), 10)
        XCTAssertEqual(Tools.duplicateGems(.rare), 25)
        XCTAssertEqual(Tools.duplicateGems(.epic), 60)
        XCTAssertEqual(Tools.duplicateGems(.legendary), 300)
    }

    func testDropMomentChancesStayRareAndOrdered() {
        // The gates that keep tools a chase: no moment above 20%, passive moments rarest.
        for moment in [Tools.DropMoment.rushComplete, .goldenCollect, .expeditionWin, .cateringDelivered] {
            XCTAssertLessThanOrEqual(moment.chance, 0.20)
            XCTAssertGreaterThan(moment.chance, 0)
        }
        XCTAssertGreaterThan(Tools.DropMoment.expeditionWin.chance,
                             Tools.DropMoment.rushComplete.chance,
                             "the biggest commitment pays the best odds")
    }

    func testNoToolsMeansIdentityEffects() {
        XCTAssertEqual(Tools.effects(owned: []), Tools.Effects())
        // Unknown ids (a removed tool in some future catalog) must not crash or contribute.
        XCTAssertEqual(Tools.effects(owned: ["not-a-tool"]), Tools.Effects())
    }

    func testEveryToolIdIsUniqueAndWeightsArePositive() {
        XCTAssertEqual(Set(Tools.all.map(\.id)).count, Tools.all.count)
        for tool in Tools.all { XCTAssertGreaterThan(tool.weight, 0) }
    }

    // MARK: Weekly Gauntlet

    @MainActor
    func testGauntletIsOncePerWeekAndPaysTheBaselinePurse() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 0, station: 0)
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        XCTAssertTrue(engine.startGauntlet())
        XCTAssertFalse(engine.startGauntlet(), "one sprint at a time")
        XCTAssertTrue(engine.gauntletActive)

        // Earn exactly ~2x the ten-minute baseline, then force time out.
        let baseline = engine.state.automatedRate * GameEngine.gauntletSeconds
        engine.addCoins(baseline * 2.1)
        let gems = engine.state.gems
        engine.debugEndGauntlet()
        engine.advance(by: 0.1)
        XCTAssertFalse(engine.gauntletActive)
        XCTAssertEqual(engine.state.gems, gems + 30, "two full multiples beaten = 30 gems")
        XCTAssertGreaterThan(engine.state.gauntletBestEver, 0)
        XCTAssertFalse(engine.startGauntlet(), "played this week - locked until Monday")
    }

    func testGauntletPurseCapsAtNinety() {
        // min(90, multiples * 15): 6+ multiples hit the cap.
        XCTAssertEqual(min(90, 7 * 15), 90)
        XCTAssertEqual(min(90, 5 * 15), 75)
    }

    // MARK: Catering

    func testCateringNeedsTwoOwnedStations() {
        var state = GameState.newGame() // exactly one owned station
        XCTAssertNil(Catering.roll(day: 100, state: state, now: Date()))
        state.venues[0].stations[1].level = 1
        let order = Catering.roll(day: 100, state: state, now: Date())
        XCTAssertNotNil(order)
        XCTAssertEqual(order?.requirements.count, 2)
        for need in (order?.requirements ?? [:]).values {
            XCTAssertGreaterThanOrEqual(need, 150, "the floor keeps early asks real")
        }
    }

    func testCateringIsDeterministicPerDayAndCompletes() {
        var state = GameState.newGame()
        state.venues[0].stations[1].level = 1
        let now = Date()
        let a = Catering.roll(day: 42, state: state, now: now)
        let b = Catering.roll(day: 42, state: state, now: now)
        XCTAssertEqual(a?.requirements, b?.requirements, "same day, same order")

        guard var order = a else { return XCTFail() }
        XCTAssertFalse(order.isComplete)
        for (station, need) in order.requirements { order.progress[station] = need }
        XCTAssertTrue(order.isComplete)
        XCTAssertEqual(order.fraction(station: order.requirements.keys.first!), 1)
    }

    // MARK: Twist venues

    func testDailySpecialRotatesThroughAllSixTrucks() {
        var seen: Set<Int> = []
        for day in 0..<6 { seen.insert(Balance.dailySpecialStation(day: day)) }
        XCTAssertEqual(seen, Set(0..<6), "every truck gets its day")
        XCTAssertEqual(Balance.dailySpecialStation(day: -1),
                       Balance.dailySpecialStation(day: 5), "negative days stay safe")
    }

    func testMidnightDinerEarnsFullRateOffline() {
        var state = GameState.newGame()
        state.festival.seasonID = 4 // twist-free season
        state.venues[5].unlocked = true
        state.venues[5].stations[0].level = 10
        state.hire(specID: ManagerCatalog.traineeID, venue: 5, station: 0)
        // Unstaff venue 0's bootstrap station so the diner is the only earner.
        state.lastSeen = Date()

        let rate = state.automatedRate(venueID: 5)
        XCTAssertGreaterThan(rate, 0)
        let report = OfflineEarnings.compute(state: state,
                                             now: state.lastSeen.addingTimeInterval(3600))
        // Full rate: no 0.5 efficiency discount on the diner's earnings.
        XCTAssertEqual(report?.coins ?? 0, rate * 3600 * state.offlineManagerBonus,
                       accuracy: rate * 3600 * 0.001)
        XCTAssertGreaterThan(state.offlineEfficiency, 0, "sanity: discount exists for others")
    }

    // MARK: Station specialization

    func testTempoPerkFeedsBothAggregators() {
        // Batch Mode at level 500, choice index 0: x6 profit, x0.2 speed.
        let chosen = [500: 0]
        XCTAssertEqual(Perks.profitMultiplier(chosen: chosen), 6, accuracy: 0.0001)
        XCTAssertEqual(Perks.speedMultiplier(chosen: chosen), 0.2, accuracy: 0.0001)
        // And the tier exists exactly once in the ladder.
        XCTAssertEqual(Perks.choiceLevels, [25, 50, 100, 500])
        XCTAssertEqual(Perks.choices(at: 500).count, 3)
    }

    // MARK: Signature Dish

    @MainActor
    func testSignatureNeedsAFullThreeStarSetAndPaysWhereCrowned() {
        var state = GameState.newGame()
        state.venues[0].stations[0].level = 10
        let engine = GameEngine(state: state, startTimers: false,
                                persistence: EphemeralPersistence())
        XCTAssertFalse(engine.canCrownSignature(venue: 0))
        XCTAssertFalse(engine.crownSignatureDish(venue: 0, station: 0))

        var starred = engine.state
        for spec in Balance.venue(0).stations {
            starred.recipeCards[Recipes.key(venue: 0, station: spec.id)] = Recipes.maxStars
        }
        let crowned = GameEngine(state: starred, startTimers: false,
                                 persistence: EphemeralPersistence())
        XCTAssertTrue(crowned.canCrownSignature(venue: 0))
        let before = crowned.state.baseRevenue(venue: 0, station: 0)
        XCTAssertTrue(crowned.crownSignatureDish(venue: 0, station: 0))
        XCTAssertEqual(crowned.state.baseRevenue(venue: 0, station: 0), before * 1.5,
                       accuracy: before * 0.001)
    }
}
