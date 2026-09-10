import XCTest
@testable import Fable

/// Covers `GameEngine.dismissManager`/`retireIdleManagers` - the "Retire" feature that lets a
/// player trim a roster that has accumulated more Common/Rare managers than any station needs,
/// and earn a small capped gem reward for doing so.
///
/// The rule that matters here is rarity, not the `premium` flag: `GameEngine
/// .isRetirementEligible` accepts Common and Rare regardless of `premium` (Sam/Tina/Otto and
/// every Rare are quest/achievement/festival rewards, so always `premium: true`, but are still
/// ordinary roster filler) and rejects Epic/Legendary regardless of `premium` (those are
/// managers a player specifically farmed or paid for). Rosters are built via
/// `addManagerForTesting`, the `#if DEBUG` seam next to it in `GameEngine`, since a fresh save
/// has 0 coins and only one free hire ever - nowhere near enough to fund the shapes these
/// tests need through the real economy.
///
/// `MARK: Gem reward` covers `Balance.managerRetirementGems(rarity:)` and the daily cap
/// (`Balance.managerRetirementDailyCap`) on rewarded retirements - dismissal itself is never
/// gated by the cap, only the payout.
@MainActor
final class ManagerDismissalTests: XCTestCase {

    private var engine: GameEngine!

    override func setUp() async throws {
        try await super.setUp()
        engine = GameEngine(state: GameState.newGame(), startTimers: false,
                            persistence: EphemeralPersistence())
    }

    override func tearDown() async throws {
        engine = nil
        try await super.tearDown()
    }

    // MARK: idleRetirableCount

    func testIdleRetirableCountAcceptsCommonAndRareButNotEpicOrAssigned() {
        engine.addManagerForTesting()                                   // common Trainee, benched
        engine.addManagerForTesting(specID: "rosa", premium: true)       // rare, benched
        engine.addManagerForTesting(specID: "vera", premium: true)       // epic, benched
        engine.addManagerForTesting(assignedTo: 0)                      // common, but working

        XCTAssertEqual(engine.idleRetirableCount, 2,
                       "only the benched common and rare should count as clutter")
    }

    // MARK: dismissManager

    func testDismissManagerRemovesAnIdleCommon() {
        let idle = engine.addManagerForTesting()

        XCTAssertNotNil(engine.dismissManager(id: idle.id))
        XCTAssertNil(engine.state.manager(id: idle.id))
    }

    func testDismissManagerAcceptsAPremiumCommon() {
        // Sam/Tina/Otto's real shape: a premium, non-Trainee common (quest/achievement reward).
        let sam = engine.addManagerForTesting(specID: "sam", premium: true)

        XCTAssertNotNil(engine.dismissManager(id: sam.id),
                        "premium must not block retirement for a Common - only rarity does")
        XCTAssertNil(engine.state.manager(id: sam.id))
    }

    func testDismissManagerAcceptsARareManager() {
        let rosa = engine.addManagerForTesting(specID: "rosa", premium: true)

        XCTAssertNotNil(engine.dismissManager(id: rosa.id))
        XCTAssertNil(engine.state.manager(id: rosa.id))
    }

    func testDismissManagerRefusesAnEpicManager() {
        let vera = engine.addManagerForTesting(specID: "vera", premium: true)

        XCTAssertNil(engine.dismissManager(id: vera.id),
                     "Epic and above must never be retirable, regardless of premium")
        XCTAssertNotNil(engine.state.manager(id: vera.id))
    }

    func testDismissManagerRefusesALegendaryManager() {
        let august = engine.addManagerForTesting(specID: "august", premium: true)

        XCTAssertNil(engine.dismissManager(id: august.id))
        XCTAssertNotNil(engine.state.manager(id: august.id))
    }

    func testDismissManagerRefusesAnAssignedManager() {
        let working = engine.addManagerForTesting(assignedTo: 0)

        XCTAssertNil(engine.dismissManager(id: working.id),
                     "a manager currently earning must not be fireable without benching first")
        XCTAssertNotNil(engine.state.manager(id: working.id))
    }

    func testDismissManagerRejectsAnUnknownID() {
        XCTAssertNil(engine.dismissManager(id: "not-a-real-id"))
    }

    // MARK: retireIdleManagers

    func testRetireIdleManagersClearsOnlyTheBenchedCommonsAndRares() {
        let idleCommon = engine.addManagerForTesting()
        let idleRare = engine.addManagerForTesting(specID: "rosa", premium: true)
        let epic = engine.addManagerForTesting(specID: "vera", premium: true)
        let working = engine.addManagerForTesting(assignedTo: 0)

        let (dismissed, gems) = engine.retireIdleManagers()

        XCTAssertEqual(dismissed, 2)
        XCTAssertEqual(gems, Balance.managerRetirementGems(.common) + Balance.managerRetirementGems(.rare))
        XCTAssertNil(engine.state.manager(id: idleCommon.id))
        XCTAssertNil(engine.state.manager(id: idleRare.id))
        XCTAssertNotNil(engine.state.manager(id: epic.id), "Epic managers must survive the sweep")
        XCTAssertNotNil(engine.state.manager(id: working.id), "a working manager must survive the sweep")
        XCTAssertEqual(engine.state.managers.count, 2)
    }

    func testRetireIdleManagersOnAClearBenchIsANoOp() {
        engine.addManagerForTesting(specID: "vera", premium: true)

        let (dismissed, gems) = engine.retireIdleManagers()
        XCTAssertEqual(dismissed, 0)
        XCTAssertEqual(gems, 0)
        XCTAssertEqual(engine.state.managers.count, 1)
    }

    // MARK: Gem reward

    func testDismissManagerGrantsTheRarityScaledGems() {
        let idle = engine.addManagerForTesting()
        let before = engine.state.gems

        let gems = engine.dismissManager(id: idle.id)

        XCTAssertEqual(gems, Balance.managerRetirementGems(.common))
        XCTAssertEqual(engine.state.gems, before + Balance.managerRetirementGems(.common))
    }

    func testRareRetirementPaysMoreThanCommon() {
        XCTAssertGreaterThan(Balance.managerRetirementGems(.rare), Balance.managerRetirementGems(.common),
                            "the gem reward must scale up with rarity, not stay flat")
    }

    /// The exploit this guards: `Balance.managerCost` doesn't scale with how many managers
    /// have already been hired, so with no cap, hiring a Trainee and immediately retiring it
    /// would be a free, repeatable coins-to-gems mint. Dismissing past the cap must still
    /// free the roster slot - only the payout stops.
    func testRewardedRetirementsCapPerDay() {
        let cap = Balance.managerRetirementDailyCap
        for _ in 0..<(cap + 3) { engine.addManagerForTesting() }
        XCTAssertEqual(engine.idleRetirableCount, cap + 3)
        let before = engine.state.gems

        let (dismissed, gems) = engine.retireIdleManagers()

        XCTAssertEqual(dismissed, cap + 3, "every idle manager is freed regardless of the reward cap")
        XCTAssertEqual(gems, cap * Balance.managerRetirementGems(.common),
                       "only the first `cap` retirements pay out")
        XCTAssertEqual(engine.state.gems, before + cap * Balance.managerRetirementGems(.common))
        XCTAssertEqual(engine.state.managers.count, 0)
    }

    /// A mixed batch should spend its capped slots on the highest-value managers first, so a
    /// capped cleanup still pays out as much as it can rather than an arbitrary subset.
    func testCappedBatchRewardsTheHighestValueManagersFirst() {
        let cap = Balance.managerRetirementDailyCap
        for _ in 0..<cap { engine.addManagerForTesting() }             // fills the cap with commons
        engine.addManagerForTesting(specID: "rosa", premium: true)     // one rare, over the cap

        let (dismissed, gems) = engine.retireIdleManagers()

        XCTAssertEqual(dismissed, cap + 1)
        XCTAssertEqual(gems, (cap - 1) * Balance.managerRetirementGems(.common) + Balance.managerRetirementGems(.rare),
                       "the rare should displace one common's reward, not lose out to list order")
    }

    func testRetirementRewardCapResetsTheNextDay() {
        for _ in 0..<Balance.managerRetirementDailyCap { engine.addManagerForTesting() }
        _ = engine.retireIdleManagers()
        XCTAssertEqual(engine.dismissManager(id: engine.addManagerForTesting().id), 0,
                      "the cap is already spent today")

        engine.debugSkip(hours: 25)

        let idle = engine.addManagerForTesting()
        XCTAssertEqual(engine.dismissManager(id: idle.id), Balance.managerRetirementGems(.common),
                      "a new calendar day resets the reward count, not just dismissal itself")
    }
}
