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
}
