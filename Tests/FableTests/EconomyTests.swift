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

    func testDeeperVenuesScaleCostAndRevenue() {
        let first = Balance.venue(0).stations[0]
        let second = Balance.venue(1).stations[0]
        XCTAssertEqual(second.baseCost / first.baseCost, 25, accuracy: 1e-6)
        XCTAssertEqual(second.baseRevenue / first.baseRevenue, 30, accuracy: 1e-6)
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
        XCTAssertEqual(Balance.starMultiplier(stars: 50), 2, accuracy: 1e-9)
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
    }
}
