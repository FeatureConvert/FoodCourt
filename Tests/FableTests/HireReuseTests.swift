import XCTest
@testable import Fable

/// Covers the reuse rule added to `GameEngine.hireManager`: an ordinary hire should staff a
/// station with a Trainee already idle on the bench before ever minting a new one. The station's
/// one-time staffing fee still applies regardless - it pays to open the station, not to
/// manufacture a person - so these tests only care about which manager ends up assigned and how
/// many exist afterward, never about coins. See also `ManagerDismissalTests`, which covers
/// cleaning up whatever had already piled up before this existed.
@MainActor
final class HireReuseTests: XCTestCase {

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

    func testOrdinaryHireReusesAnIdleTraineeInsteadOfMintingANew() {
        let idle = engine.addManagerForTesting()

        XCTAssertTrue(engine.hireManager(for: 0, free: true))

        XCTAssertEqual(engine.state.managers.count, 1, "the idle trainee should be reused, not joined by a new one")
        XCTAssertEqual(engine.state.assignment(of: idle.id)?.station, 0, "the reused trainee should now staff the station")
        XCTAssertEqual(engine.idleRetirableCount, 0)
    }

    func testOrdinaryHireStillMintsAFreshTraineeWhenTheBenchHasNone() {
        XCTAssertTrue(engine.hireManager(for: 0, free: true))

        XCTAssertEqual(engine.state.managers.count, 1)
        XCTAssertNotNil(engine.state.assignment(of: engine.state.managers[0].id))
    }

    func testOrdinaryHireIgnoresAPremiumIdleManagerAndMintsATraineeInstead() {
        let premiumIdle = engine.addManagerForTesting(premium: true)

        XCTAssertTrue(engine.hireManager(for: 0, free: true))

        XCTAssertEqual(engine.state.managers.count, 2, "a premium manager must never be swept up as filler")
        XCTAssertNil(engine.state.assignment(of: premiumIdle.id), "the premium manager must stay on the bench, untouched")
    }

    func testPremiumHireAlwaysMintsFreshEvenWithAnIdleTraineeAvailable() {
        let idle = engine.addManagerForTesting()

        XCTAssertTrue(engine.hireManager(for: 0, free: true, premium: true))

        XCTAssertEqual(engine.state.managers.count, 2,
                       "reusing the idle trainee for a premium hire would upgrade it to prestige-proof for free")
        XCTAssertNil(engine.state.assignment(of: idle.id), "the original idle trainee must stay untouched on the bench")
        let hired = engine.state.managers.first { $0.id != idle.id }
        XCTAssertEqual(hired?.premium, true)
        XCTAssertEqual(engine.state.assignment(of: hired?.id ?? "")?.station, 0)
    }

    func testReuseDoesNotResurrectAManagerCurrentlyOnAnErrand() {
        let onErrand = engine.addManagerForTesting()
        XCTAssertTrue(engine.startErrand(managerID: onErrand.id, hours: Errands.options.first?.hours ?? 1))

        XCTAssertTrue(engine.hireManager(for: 0, free: true))

        XCTAssertEqual(engine.state.managers.count, 2, "a manager away on an errand is not idle and must not be reused")
        XCTAssertNil(engine.state.assignment(of: onErrand.id))
    }
}
