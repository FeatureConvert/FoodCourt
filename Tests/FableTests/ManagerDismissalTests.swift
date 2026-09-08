import XCTest
@testable import Fable

/// Covers `GameEngine.dismissManager`/`dismissIdleTrainees` - the "Let Go" feature that lets a
/// player trim a roster that has accumulated more coin-hired Trainees than any station needs.
///
/// The one rule that matters here is `!premium`: it is the same survivor test `prestige()`
/// already applies to the whole roster (`state.managers.removeAll { !$0.premium }`), and it is
/// the only thing standing between this feature and accidentally deleting a named hire. Every
/// test below leans on that boundary rather than on `specID`, because `premium` is what the
/// engine actually checks. Rosters are built via `addManagerForTesting`, the `#if DEBUG` seam
/// next to it in `GameEngine`, since a fresh save has 0 coins and only one free hire ever -
/// nowhere near enough to fund the shapes these tests need through the real economy.
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

    // MARK: idleTraineeCount

    func testIdleTraineeCountIgnoresPremiumAndAssignedManagers() {
        engine.addManagerForTesting()
        engine.addManagerForTesting(premium: true)
        engine.addManagerForTesting(assignedTo: 0)

        XCTAssertEqual(engine.idleTraineeCount, 1,
                       "only the bare, benched, non-premium trainee should count as clutter")
    }

    // MARK: dismissManager

    func testDismissManagerRemovesAnIdleNonPremiumTrainee() {
        let idle = engine.addManagerForTesting()

        XCTAssertTrue(engine.dismissManager(id: idle.id))
        XCTAssertNil(engine.state.manager(id: idle.id))
    }

    func testDismissManagerRefusesAPremiumManager() {
        let premium = engine.addManagerForTesting(premium: true)

        XCTAssertFalse(engine.dismissManager(id: premium.id))
        XCTAssertNotNil(engine.state.manager(id: premium.id),
                        "a premium hire must survive even a direct dismiss request")
    }

    func testDismissManagerRefusesAnAssignedManager() {
        let working = engine.addManagerForTesting(assignedTo: 0)

        XCTAssertFalse(engine.dismissManager(id: working.id))
        XCTAssertNotNil(engine.state.manager(id: working.id),
                        "a manager currently earning must not be fireable without benching first")
    }

    func testDismissManagerRejectsAnUnknownID() {
        XCTAssertFalse(engine.dismissManager(id: "not-a-real-id"))
    }

    // MARK: dismissIdleTrainees

    func testDismissIdleTraineesClearsOnlyTheBenchedNonPremiumOnes() {
        let idleA = engine.addManagerForTesting()
        let idleB = engine.addManagerForTesting()
        let premium = engine.addManagerForTesting(premium: true)
        let working = engine.addManagerForTesting(assignedTo: 0)

        let dismissed = engine.dismissIdleTrainees()

        XCTAssertEqual(dismissed, 2)
        XCTAssertNil(engine.state.manager(id: idleA.id))
        XCTAssertNil(engine.state.manager(id: idleB.id))
        XCTAssertNotNil(engine.state.manager(id: premium.id), "premium managers must survive the sweep")
        XCTAssertNotNil(engine.state.manager(id: working.id), "a working manager must survive the sweep")
        XCTAssertEqual(engine.state.managers.count, 2)
    }

    func testDismissIdleTraineesOnAClearBenchIsANoOp() {
        engine.addManagerForTesting(premium: true)

        XCTAssertEqual(engine.dismissIdleTrainees(), 0)
        XCTAssertEqual(engine.state.managers.count, 1)
    }
}
