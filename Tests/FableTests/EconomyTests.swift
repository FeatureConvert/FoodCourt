import XCTest
@testable import Fable

/// Covers the arithmetic that is impossible to eyeball in a running game: the closed-form
/// cost curve, milestone stacking, and prestige scaling.
final class EconomyTests: XCTestCase {

    private var spec: StationSpec { Balance.venue(0).stations[0] }

    // MARK: Cost curve

    func testFirstPurchaseCostsBasePrice() {
        XCTAssertEqual(Balance.cost(spec: spec, level: 0, quantity: 1), spec.baseCost, accuracy: 1e-9)
    }

    func testBulkCostMatchesIterativeSum() {
        // The closed-form geometric sum is the risky part - check it against the obvious
        // loop it replaced.
        for start in [0, 1, 7, 43, 260] {
            for quantity in [1, 10, 100] {
                var reference: Double = 0
                for step in 0..<quantity {
                    reference += spec.baseCost * pow(spec.costGrowth, Double(start + step))
                }
                let closedForm = Balance.cost(spec: spec, level: start, quantity: quantity)
                XCTAssertEqual(closedForm, reference, accuracy: reference * 1e-9,
                               "level \(start) qty \(quantity)")
            }
        }
    }

    func testZeroQuantityIsFree() {
        XCTAssertEqual(Balance.cost(spec: spec, level: 5, quantity: 0), 0)
    }

    // MARK: Max affordable

    func testMaxAffordableNeverOverspends() {
        for coins in [0.0, 3.0, 4.0, 100.0, 5_000.0, 1e7, 1e15] {
            let n = Balance.maxAffordable(spec: spec, level: 0, coins: coins)
            let spend = Balance.cost(spec: spec, level: 0, quantity: n)
            XCTAssertLessThanOrEqual(spend, coins, "bought \(n) for \(coins)")

            // ...and that it is genuinely the maximum: one more must be unaffordable.
            let oneMore = Balance.cost(spec: spec, level: 0, quantity: n + 1)
            XCTAssertGreaterThan(oneMore, coins, "should not have stopped at \(n) with \(coins)")
        }
    }

    func testCannotAffordFirstLevel() {
        XCTAssertEqual(Balance.maxAffordable(spec: spec, level: 0, coins: spec.baseCost - 0.01), 0)
        XCTAssertEqual(Balance.maxAffordable(spec: spec, level: 0, coins: spec.baseCost), 1)
    }

    // MARK: Milestones

    func testMilestonesStackMultiplicatively() {
        XCTAssertEqual(Balance.profitMultiplier(level: 99), 1)
        XCTAssertEqual(Balance.speedMultiplier(level: 40), 2)
        XCTAssertEqual(Balance.profitMultiplier(level: 100), 2)
        XCTAssertEqual(Balance.speedMultiplier(level: 250), 4)
        XCTAssertEqual(Balance.profitMultiplier(level: 500), 6)    // 2 x 3
        XCTAssertEqual(Balance.speedMultiplier(level: 1000), 8)    // 2 x 2 x 2
        XCTAssertEqual(Balance.profitMultiplier(level: 2000), 24)  // 2 x 3 x 4
    }

    func testCycleTimeShrinksWithSpeedMilestonesButIsFloored() {
        let base = Balance.cycleTime(spec: spec, level: 1)
        XCTAssertEqual(base, spec.baseCycle, accuracy: 1e-9)
        XCTAssertEqual(Balance.cycleTime(spec: spec, level: 40), spec.baseCycle / 2, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(Balance.cycleTime(spec: spec, level: 10_000), Balance.minimumCycle)
    }

    func testNextMilestoneAdvances() {
        XCTAssertEqual(Balance.nextMilestone(level: 0)?.level, 40)
        XCTAssertEqual(Balance.nextMilestone(level: 40)?.level, 100)
        XCTAssertNil(Balance.nextMilestone(level: 2000))
    }

    func testUnownedStationEarnsNothing() {
        XCTAssertEqual(Balance.revenuePerCycle(spec: spec, level: 0), 0)
    }

    // MARK: Venue scaling

    /// Revenue and cost intentionally share the same base (25x/venue) - a real long-horizon
    /// simulation showed a mismatched 30x-revenue/25x-cost split compounding into each
    /// subsequent venue being mathematically more profit-efficient than the last, which
    /// measured as an accelerating venue-to-venue pace (21m/17m/10m/6.5m/4.5m/3.5m across
    /// Burger through Food Truck) matching a live report of exactly that symptom.
    func testDeeperVenuesScaleCostAndRevenueAtTheSameRate() {
        let first = Balance.venue(0).stations[0]
        let second = Balance.venue(1).stations[0]
        XCTAssertEqual(second.baseCost / first.baseCost, 25, accuracy: 1e-6)
        XCTAssertEqual(second.baseRevenue / first.baseRevenue, 25, accuracy: 1e-6)
    }

    func testEveryVenueHasAFullStationSet() {
        for venue in Balance.venues {
            XCTAssertEqual(venue.stations.count, 6, "\(venue.name)")
            XCTAssertEqual(venue.stations.last?.art, .plate, "capstone art for \(venue.name)")
        }
    }

    // MARK: Prestige

    func testStarsScaleWithSquareRootOfLifetime() {
        XCTAssertEqual(Balance.totalStars(lifetimeEarnings: 0), 0)
        XCTAssertEqual(Balance.totalStars(lifetimeEarnings: 1e12), 150)
        // Four times the earnings should be exactly twice the stars.
        XCTAssertEqual(Balance.totalStars(lifetimeEarnings: 4e12), 300)
    }

    func testPendingStarsSubtractStarsAlreadyHeld() {
        XCTAssertEqual(Balance.pendingStars(lifetimeEarnings: 4e12, currentStars: 150), 150)
        XCTAssertEqual(Balance.pendingStars(lifetimeEarnings: 1e12, currentStars: 400), 0)
    }

    func testStarMultiplier() {
        XCTAssertEqual(Balance.starMultiplier(stars: 0), 1)
        XCTAssertEqual(Balance.starMultiplier(stars: 500), 4, accuracy: 1e-9,
                       "the reference point the whole sqrt curve is tuned against")
        XCTAssertEqual(Balance.starMultiplier(stars: 50), 1 + 3 * (0.1).squareRoot(), accuracy: 1e-9)
    }

    /// The bonus has to grow slower than linearly with stars, or it feeds a runaway: more
    /// stars -> more permanent profit -> lifetime earnings climb faster -> the next prestige
    /// lands sooner too, compounding without limit (this exact loop took a real save from
    /// 16K stars to ~1.7e19 in one session before the fix). Doubling the star count must
    /// never double the bonus.
    func testStarMultiplierGrowsSlowerThanLinearly() {
        let bonusAt1k = Balance.starMultiplier(stars: 1_000) - 1
        let bonusAt2k = Balance.starMultiplier(stars: 2_000) - 1
        XCTAssertLessThan(bonusAt2k, bonusAt1k * 2,
                          "doubling stars must give less than double the profit bonus")

        let bonusAt10k = Balance.starMultiplier(stars: 10_000) - 1
        let bonusAt20k = Balance.starMultiplier(stars: 20_000) - 1
        XCTAssertLessThan(bonusAt20k, bonusAt10k * 2)
    }

    /// Lifetime earnings large enough to reproduce the incident referenced above - a real
    /// save's star count reached ~1.7e19, which means its `lifetimeEarnings` (stars scale
    /// with its square root) was around 1.28e46. Converting a raw value that size straight
    /// to `Int` traps (Int64.max is ~9.22e18), which would crash any view that computes
    /// `pendingStars`, not just misbehave. Must clamp, never crash.
    func testTotalStarsNeverCrashesOnAstronomicalEarnings() {
        XCTAssertEqual(Balance.totalStars(lifetimeEarnings: 1.28e46), Balance.maxSaneLifetimeStars)
        XCTAssertEqual(Balance.totalStars(lifetimeEarnings: 1e300), Balance.maxSaneLifetimeStars)
        XCTAssertEqual(Balance.totalStars(lifetimeEarnings: .infinity), Balance.maxSaneLifetimeStars)
        // Comfortably below the ceiling should still compute normally, not just always
        // return the cap - the guard is a ceiling, not a replacement for the real formula.
        XCTAssertLessThan(Balance.totalStars(lifetimeEarnings: 1e15), Balance.maxSaneLifetimeStars)
    }

    /// `maxSaneLifetimeEarnings` must actually map back to `maxSaneLifetimeStars` under the
    /// real formula, or the two ceilings could silently drift apart after a future retune.
    func testSaneCeilingsStayConsistentWithEachOther() {
        XCTAssertEqual(Balance.totalStars(lifetimeEarnings: Balance.maxSaneLifetimeEarnings),
                       Balance.maxSaneLifetimeStars, accuracy: 1)
    }

    // MARK: Award-proportional research pricing

    func testResearchCostSitsOnStaticFloorForSmallAwards() {
        let node = Research.node("prep")!
        // A brand-new player (award 0) and an early player pay exactly the old curve.
        XCTAssertEqual(node.cost(forRank: 0, award: 0), node.cost(forRank: 0))
        XCTAssertEqual(node.cost(forRank: 0, award: 50), 30,
                       "0.4 x 50 = 20 loses to the 30-star floor")
    }

    func testResearchCostScalesWithTheLatestAward() {
        let node = Research.node("prep")!
        XCTAssertEqual(node.cost(forRank: 0, award: 10_000), 4_000,
                       "0.4 x award once that beats the floor")
        XCTAssertEqual(node.cost(forRank: 0, award: 1_000_000), 400_000)
        // The floor still wins for deep ranks vs small awards.
        XCTAssertEqual(node.cost(forRank: 9, award: 100),
                       node.cost(forRank: 9))
    }

    /// The pacing property the whole rework exists for: a Franchise award funds roughly
    /// 1/fraction ranks, so the 90-rank tree is a months-long ladder of prestiges at any
    /// income level - the award scales with the player, the affordable rank count doesn't.
    func testOneAwardFundsRoughlyTwoToThreeRanks() {
        for award in [50_000, 5_000_000, 500_000_000] {
            var ranks: [String: Int] = [:]
            var budget = award
            var bought = 0
            while bought < 90 {
                let affordable = Research.nodes
                    .filter { Research.canBuy($0, ranks: ranks, stars: budget, award: award) }
                    .map { ($0, $0.cost(forRank: ranks[$0.id] ?? 0, award: award)) }
                    .min { $0.1 < $1.1 }
                guard let (node, cost) = affordable else { break }
                budget -= cost
                ranks[node.id] = (ranks[node.id] ?? 0) + 1
                bought += 1
            }
            XCTAssertTrue((2...3).contains(bought),
                          "award \(award) bought \(bought) ranks - pacing drifted")
        }
    }

    private func roundTrip(_ state: GameState) throws -> GameState {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GameState.self, from: encoder.encode(state))
    }

    /// The actual repair path: a save whose numbers are still representable (so it decodes
    /// cleanly, unlike the still-worse case of a literal too large for `Int` to parse at
    /// all) but were corrupted by the runaway must come back down to the sane ceiling on
    /// load, not just at display time - otherwise the very next prestige recomputes an
    /// equally absurd award from the still-corrupted `lifetimeEarnings` and undoes nothing.
    func testDecodingRepairsACorruptedSave() throws {
        var state = GameState.newGame()
        state.lifetimeStars = 50_000_000_000_000   // 5e13, past the 1e10 sane ceiling
        state.stars = 50_000_000_000_000
        state.lifetimeEarnings = 1e30

        let decoded = try roundTrip(state)

        XCTAssertEqual(decoded.lifetimeStars, Balance.maxSaneLifetimeStars)
        XCTAssertEqual(decoded.lifetimeEarnings, Balance.maxSaneLifetimeEarnings, accuracy: 1)
        XCTAssertLessThanOrEqual(decoded.stars, decoded.lifetimeStars)
    }

    /// The repair check must never touch a save that never crossed the line - it should be
    /// invisible to every normal player, not just harmless.
    func testDecodingLeavesNormalSavesUntouched() throws {
        var state = GameState.newGame()
        state.lifetimeStars = 500
        state.stars = 200
        state.lifetimeEarnings = 5e12

        let decoded = try roundTrip(state)

        XCTAssertEqual(decoded.lifetimeStars, 500)
        XCTAssertEqual(decoded.stars, 200)
        XCTAssertEqual(decoded.lifetimeEarnings, 5e12, accuracy: 1)
    }

    // MARK: Staleness (organic-growth cap)

    func testStalenessMultiplierIsFlatWithinTheGracePeriod() {
        XCTAssertEqual(Balance.stalenessMultiplier(boardAgeHours: 0), 1)
        XCTAssertEqual(Balance.stalenessMultiplier(boardAgeHours: Balance.staleGraceHours), 1)
        XCTAssertEqual(Balance.stalenessMultiplier(boardAgeHours: Balance.staleGraceHours - 0.01), 1)
    }

    func testStalenessMultiplierGrowsPastTheGracePeriod() {
        let atGrace = Balance.stalenessMultiplier(boardAgeHours: Balance.staleGraceHours)
        let aDayPast = Balance.stalenessMultiplier(boardAgeHours: Balance.staleGraceHours + 24)
        let aWeekPast = Balance.stalenessMultiplier(boardAgeHours: Balance.staleGraceHours + 24 * 7)
        XCTAssertGreaterThan(aDayPast, atGrace)
        XCTAssertGreaterThan(aWeekPast, aDayPast, "further stalling keeps getting pricier, not flattening out")
    }

    // MARK: Formatting

    func testNumberAbbreviation() {
        XCTAssertEqual(Format.currency(999), "999")
        XCTAssertEqual(Format.currency(1_000), "1.00K")
        XCTAssertEqual(Format.currency(12_340), "12.3K")
        XCTAssertEqual(Format.currency(123_400), "123K")
        XCTAssertEqual(Format.currency(1_000_000), "1.00M")
        XCTAssertEqual(Format.currency(1e12), "1.00T")
        // Past trillions the suffix ladder takes over.
        XCTAssertEqual(Format.currency(1e15), "1.00aa")
        XCTAssertEqual(Format.currency(1e18), "1.00ab")
    }

    /// The shop renders each IAP section in catalog order, so catalog order IS the display
    /// order - keep both sections ascending by dollar value. Lives here rather than in
    /// StoreTests because it's pure catalog data and must run on CLI too (StoreTests skips
    /// itself without an Xcode StoreKit session).
    func testShopSectionsAreOrderedByPrice() {
        for (name, section) in [("offers", ShopCatalog.offers), ("gemPacks", ShopCatalog.gemPacks)] {
            let prices = section.map { Double($0.fallbackPrice.dropFirst()) ?? -1 }
            XCTAssertFalse(prices.contains(-1), "\(name): unparseable fallback price")
            XCTAssertEqual(prices, prices.sorted(), "\(name) must ascend by price")
        }
    }

    func testPricesNeverRenderLowerThanTheyCost() {
        // The bug this guards: the first station upgrade costs 4.72, and currency() rendered
        // it "4" - the same string a 4.0 balance renders as - so the buy button looked
        // affordable while the engine correctly refused it.
        XCTAssertEqual(Format.currency(4.72), "4", "balances truncate, which is what broke this")
        XCTAssertEqual(Format.price(4.72), "5")
        XCTAssertEqual(Format.price(4.0), "4", "an exact price must not inflate")

        // Above a thousand the mantissa rounds up at the printed precision.
        XCTAssertEqual(Format.price(1_000), "1.00K")
        XCTAssertEqual(Format.price(1_234.5), "1.24K")
        XCTAssertEqual(Format.price(12_341), "12.4K")
        XCTAssertEqual(Format.price(123_401), "124K")

        // Rounding up can tip the mantissa into the next tier rather than print 4 digits.
        XCTAssertEqual(Format.price(999_600), "1.00M")

        XCTAssertEqual(Format.price(0), "0")
    }

    /// The real-world case: a brand-new player at station level 1 must never see a price
    /// they cannot actually pay.
    func testFirstUpgradePriceIsNotUnderstated() {
        let spec = Balance.venue(0).stations[0]
        let cost = Balance.cost(spec: spec, level: 1, quantity: 1)
        let shown = Format.price(cost)
        XCTAssertEqual(shown, "5")
        XCTAssertGreaterThanOrEqual(Double(shown) ?? 0, cost,
                                    "the number on the button has to cover the real cost")
    }

    func testDurationFormatting() {
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(90), "1m 30s")
        XCTAssertEqual(Format.duration(9_000), "2h 30m")
        // A festival/league week-long countdown - "167h 47m" is a raw hour count nobody reads
        // faster than "6d 23h".
        XCTAssertEqual(Format.duration(603_247), "6d 23h")
        XCTAssertEqual(Format.duration(86_400), "1d 0h")
    }
}
