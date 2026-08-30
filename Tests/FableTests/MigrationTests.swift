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

    /// VenueState, TutorialState, and FestivalState all default every field, but until this
    /// pass they still used the synthesized Decodable, which throws keyNotFound on ANY missing
    /// key rather than falling back to that default - a field added to any of them later would
    /// have aborted the whole save decode, not just that one feature. Confirms all three now
    /// decode an empty object into their documented defaults instead of throwing.
    func testFieldlessStatesDecodeToTheirDefaults() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let empty = "{}".data(using: .utf8)!

        let venue = try decoder.decode(VenueState.self, from: empty)
        XCTAssertEqual(venue, VenueState())

        let tutorial = try decoder.decode(TutorialState.self, from: empty)
        XCTAssertEqual(tutorial, TutorialState())

        let festival = try decoder.decode(FestivalState.self, from: empty)
        XCTAssertEqual(festival.seasonID, 1)
        XCTAssertEqual(festival.tickets, 0)
        XCTAssertTrue(festival.claimedFree.isEmpty)
        XCTAssertFalse(festival.premiumUnlocked)
    }

    /// LeagueState and LeagueRival were the one place left still using `try c.decode` (hard
    /// required, no fallback) for their original fields - unlike every sibling type here. A
    /// save with the "league" key present but missing even one of those fields threw out of
    /// LeagueState.init, and since GameState decodes it via
    /// `decodeIfPresent(...) ?? LeagueState()`, that throw propagated through decodeIfPresent
    /// too (it only swallows an ABSENT key, not a present-but-malformed value) and took the
    /// WHOLE save down - not just League progress. Confirms both now decode a fieldless object
    /// into their documented defaults, and that a realistic partial "league" blob no longer
    /// wipes the rest of a GameState decode.
    func testLeagueStateAndRivalSurviveMissingFieldsWithoutWipingTheWholeSave() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let empty = "{}".data(using: .utf8)!

        let league = try decoder.decode(LeagueState.self, from: empty)
        XCTAssertEqual(league.tier, .bronze)
        XCTAssertEqual(league.score, 0)
        XCTAssertTrue(league.rivals.isEmpty)
        XCTAssertEqual(league.seasonsPlayed, 0)

        let rival = try decoder.decode(LeagueRival.self, from: empty)
        XCTAssertEqual(rival.id, 0)
        XCTAssertEqual(rival.name, "Rival")
        XCTAssertEqual(rival.score, 0)

        // The actual failure mode: a whole-save decode with "league" present but incomplete
        // (score given, everything else - including one rival missing its own score - absent
        // or malformed) must still succeed rather than throwing and losing everything else in
        // the save.
        let state = try decode("""
        {"coins": 500, "league": {"score": 1200, "rivals": [{"id": 3, "name": "Rossi's"}]}}
        """)
        XCTAssertEqual(state.coins, 500, "the rest of the save must survive a malformed league")
        XCTAssertEqual(state.league.score, 1200)
        XCTAssertEqual(state.league.tier, .bronze, "missing field falls back to its default")
        XCTAssertEqual(state.league.rivals.first?.name, "Rossi's")
        XCTAssertEqual(state.league.rivals.first?.score, 0, "missing rival field falls back too")
    }

    /// BoostState and ActiveQuest don't have a natural default for every field, so their
    /// hardened decoders lean conservative on purpose: a corrupt/incomplete boost decodes as
    /// already-expired (inert), and a corrupt/incomplete quest decodes as permanently
    /// unfinishable (target set just above whatever progress it got) - neither can hand the
    /// player something they didn't earn. Confirms both actually land there instead of
    /// throwing or, worse, decoding as already complete/active.
    func testCorruptBoostAndQuestDecodeAsInertRatherThanThrowingOrGrantingSomething() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let empty = "{}".data(using: .utf8)!

        let boost = try decoder.decode(BoostState.self, from: empty)
        XCTAssertFalse(boost.isActive(at: Date()), "a fieldless boost must decode as already-expired")
        XCTAssertEqual(boost.multiplier, 1, "a neutral multiplier, not a free bonus")

        let quest = try decoder.decode(ActiveQuest.self, from: empty)
        XCTAssertFalse(quest.isComplete, "a fieldless quest must never decode as already claimable")
        XCTAssertEqual(quest.rewardGems, 0)

        // Same guarantee even when SOME fields are present and only the rest are missing.
        let partial = try decoder.decode(ActiveQuest.self,
            from: "{\"progress\": 500}".data(using: .utf8)!)
        XCTAssertFalse(partial.isComplete, "target must land above whatever progress decoded to")
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
