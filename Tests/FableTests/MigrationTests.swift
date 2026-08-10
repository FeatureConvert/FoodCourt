import XCTest
@testable import Fable

/// Pre-publish migration matrix: saves from every era of this game's development must
/// decode into a playable, sane state - a wiped or crashing veteran save on update day is
/// the one bug there is no apologizing for.
final class MigrationTests: XCTestCase {

    private func decode(_ json: String) throws -> GameState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var state = try decoder.decode(GameState.self, from: json.data(using: .utf8)!)
        state.reconcileWithCatalog()
        return state
    }

    /// A schema-1 launch-era save: five venues, hasManager flags, the old ad-cooldown key,
    /// none of the thirty systems that came later.
    func testLaunchEraSaveDecodesPlayable() throws {
        let json = """
        {"schemaVersion": 1, "coins": 123456.0, "gems": 80, "stars": 12,
         "venues": [{"unlocked": true, "stations": [
            {"level": 40, "hasManager": true}, {"level": 10, "hasManager": false},
            {"level": 0}, {"level": 0}, {"level": 0}, {"level": 0}]}],
         "currentVenue": 0, "adAvailableAt": "2025-01-01T00:00:00Z",
         "lastSeen": "2025-01-01T00:00:00Z", "timeOffset": 0}
        """
        let state = try decode(json)
        XCTAssertEqual(state.coins, 123456)
        XCTAssertEqual(state.venues.count, Balance.venues.count, "gains every newer venue")
        XCTAssertEqual(state.venues[0].stations[0].level, 40)
        XCTAssertEqual(state.managers.count, 1, "hasManager migrated to a real Trainee")
        XCTAssertTrue(state.venues[0].stations[0].isStaffed)
        XCTAssertEqual(state.lifetimeStars, 12, "pre-spendable-stars seeding")
        XCTAssertTrue(state.tutorial.finished, "a save with history skips the tutorial")
        XCTAssertNil(state.contract, "never prestiged - no contract owed or active")
        XCTAssertTrue(state.tools.isEmpty)
        // And it computes without trapping anywhere that matters.
        XCTAssertGreaterThan(state.automatedRate, 0)
        _ = state.globalMultiplier
        _ = GoalDirector.currentGoal(for: state)
    }

    /// A pre-depth-marathon save: prestiged veteran with research, from before contracts,
    /// tools, catering, the gauntlet, twist venues, or the legacy tree existed.
    func testPreMarathonVeteranSaveDecodesPlayable() throws {
        let json = """
        {"schemaVersion": 2, "coins": 1e15, "gems": 900, "stars": 4000,
         "lifetimeStars": 60000, "lifetimeEarnings": 5e14, "runEarnings": 1e12,
         "prestigeCount": 7, "research": {"prep": 5, "brand": 2},
         "legacy": {"level": 1},
         "venues": [{"unlocked": true, "stations": [
            {"level": 120, "managerID": "m1"}, {"level": 80}, {"level": 0},
            {"level": 0}, {"level": 0}, {"level": 0}]}],
         "managers": [{"id": "m1", "specID": "sam", "premium": true}],
         "currentVenue": 0, "lastSeen": "2026-06-01T00:00:00Z",
         "seenIntros": ["welcome", "prestige"], "timeOffset": 0}
        """
        let state = try decode(json)
        XCTAssertEqual(state.prestigeCount, 7)
        XCTAssertEqual(state.research["prep"], 5, "research intact")
        XCTAssertEqual(state.contract?.id, "straight",
                       "mid-run veterans default to the vanilla contract, not an owed pick")
        XCTAssertEqual(state.legacyPerks, [:],
                       "one perk owed for the existing legacy level - offered, not lost")
        XCTAssertEqual(state.lastPrestigeAward, 0, "static research floor until next franchise")
        XCTAssertFalse(state.landmarksCrossed.isEmpty,
                       "5e14 lifetime backfills landmarks silently - no toast storm")
        XCTAssertEqual(state.managers.first?.bondDays ?? -1, 0)
        XCTAssertGreaterThan(state.automatedRate, 0)
    }

    /// Round-trip fuzz: fifty randomized states must survive encode -> decode with every
    /// load-bearing field intact. Guards against a CodingKeys/decodeIfPresent mismatch in
    /// any of the ~30 fields added across the marathon.
    func testRandomizedStatesRoundTripLosslessly() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var rng = SystemRandomNumberGenerator()

        for seed in 0..<50 {
            var state = GameState.newGame()
            state.coins = Double.random(in: 0...1e20, using: &rng)
            state.gems = Int.random(in: 0...100_000, using: &rng)
            state.stars = Int.random(in: 0...1_000_000, using: &rng)
            state.lifetimeStars = state.stars + Int.random(in: 0...1_000_000, using: &rng)
            state.lifetimeEarnings = Double.random(in: 0...1e24, using: &rng)
            state.prestigeCount = Int.random(in: 0...60, using: &rng)
            state.lastPrestigeAward = Int.random(in: 0...5_000_000, using: &rng)
            state.legacy.level = Int.random(in: 0...5, using: &rng)
            state.legacyPerks = ["capital": Int.random(in: 0...3, using: &rng)]
            // nil only ever means "never prestiged"; an owed pick is the explicit sentinel.
            state.activeContract = state.prestigeCount == 0 ? nil
                : (Bool.random(using: &rng) ? "nightowl" : Contracts.unchosenID)
            state.tools = Bool.random(using: &rng) ? ["goldspatula", "spoon"] : []
            state.venueMastery = [0: Int.random(in: 0...3, using: &rng)]
            state.rushChain = Int.random(in: 0...3, using: &rng)
            state.perkChoicesUsed = Int.random(in: 0...4, using: &rng)
            state.gauntletBestEver = Double.random(in: 0...1e18, using: &rng)
            state.expeditionWins = Int.random(in: 0...200, using: &rng)
            state.bestFestivalTier = Int.random(in: 0...30, using: &rng)
            state.signatureDish = [2: Int.random(in: 0...5, using: &rng)]

            let decoded = try decoder.decode(GameState.self,
                                             from: encoder.encode(state))
            XCTAssertEqual(decoded.gems, state.gems, "seed \(seed)")
            XCTAssertEqual(decoded.stars, state.stars, "seed \(seed)")
            XCTAssertEqual(decoded.prestigeCount, state.prestigeCount, "seed \(seed)")
            XCTAssertEqual(decoded.lastPrestigeAward, state.lastPrestigeAward, "seed \(seed)")
            XCTAssertEqual(decoded.legacyPerks, state.legacyPerks, "seed \(seed)")
            XCTAssertEqual(decoded.activeContract, state.activeContract, "seed \(seed)")
            XCTAssertEqual(decoded.tools, state.tools, "seed \(seed)")
            XCTAssertEqual(decoded.venueMastery, state.venueMastery, "seed \(seed)")
            XCTAssertEqual(decoded.rushChain, state.rushChain, "seed \(seed)")
            XCTAssertEqual(decoded.perkChoicesUsed, state.perkChoicesUsed, "seed \(seed)")
            XCTAssertEqual(decoded.gauntletBestEver, state.gauntletBestEver, "seed \(seed)")
            XCTAssertEqual(decoded.expeditionWins, state.expeditionWins, "seed \(seed)")
            XCTAssertEqual(decoded.bestFestivalTier, state.bestFestivalTier, "seed \(seed)")
            XCTAssertEqual(decoded.signatureDish, state.signatureDish, "seed \(seed)")
            // The corruption clamp may adjust star fields above the sane ceiling -
            // everything else must be byte-faithful.
            if state.lifetimeStars <= Balance.maxSaneLifetimeStars,
               state.lifetimeEarnings <= Balance.maxSaneLifetimeEarnings {
                XCTAssertEqual(decoded.lifetimeStars, state.lifetimeStars, "seed \(seed)")
            }
        }
    }
}
