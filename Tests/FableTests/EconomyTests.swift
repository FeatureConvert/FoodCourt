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

    func testDurationFormatting() {
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(90), "1m 30s")
        XCTAssertEqual(Format.duration(9_000), "2h 30m")
    }
}
