import Foundation

// MARK: - Persisted model

struct StationState: Codable, Equatable {
    var level: Int = 0
    /// Legacy flag from schema 1. Kept only so old saves decode; migration moves it onto a
    /// real manager instance and nothing reads it afterwards.
    var hasManager: Bool = false
    /// Seconds elapsed into the current cycle. Only meaningful while `isRunning`.
    var elapsed: TimeInterval = 0
    var isRunning: Bool = false
    /// Instance id of the manager running this station, if any.
    var managerID: String? = nil
    /// Milestone level -> chosen perk index.
    var perks: [Int: Int] = [:]

    var isOwned: Bool { level > 0 }
    var isStaffed: Bool { managerID != nil }

    enum CodingKeys: String, CodingKey {
        case level, hasManager, elapsed, isRunning, managerID, perks
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        hasManager = try c.decodeIfPresent(Bool.self, forKey: .hasManager) ?? false
        elapsed = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsed) ?? 0
        isRunning = try c.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
        managerID = try c.decodeIfPresent(String.self, forKey: .managerID)
        perks = try c.decodeIfPresent([Int: Int].self, forKey: .perks) ?? [:]
    }
}

struct VenueState: Codable, Equatable {
    var unlocked: Bool = false
    var stations: [StationState] = []

    static func fresh(venue: VenueSpec, unlocked: Bool) -> VenueState {
        VenueState(unlocked: unlocked, stations: venue.stations.map { _ in StationState() })
    }
}

/// A timed global profit multiplier. Several can stack; the engine multiplies them together.
struct BoostState: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var multiplier: Double
    var expiry: Date

    func isActive(at now: Date) -> Bool { expiry > now }
    func remaining(at now: Date) -> TimeInterval { max(0, expiry.timeIntervalSince(now)) }
}

/// Non-consumable purchases. Kept separate from currency so a restore can rebuild them
/// without touching the player's coin balance.
struct Entitlements: Codable, Equatable {
    var vip: Bool = false
    var starterPack: Bool = false
    var grandOpeningBundle: Bool = false

    var profitMultiplier: Double { vip ? 1 + Balance.vipProfitBonus : 1 }
    /// VIP carries the Carnival Pass, every season, for as long as they hold it.
    var includesFestivalPremium: Bool { vip }

    enum CodingKeys: String, CodingKey { case vip, starterPack, grandOpeningBundle }

    init() {}

    /// Hand-written for the same reason as `GameState`'s: a synthesized decoder throws on
    /// any key an older save doesn't have yet, which would fail the whole save's decode -
    /// not just this one flag - the moment a new entitlement is added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vip = try c.decodeIfPresent(Bool.self, forKey: .vip) ?? false
        starterPack = try c.decodeIfPresent(Bool.self, forKey: .starterPack) ?? false
        grandOpeningBundle = try c.decodeIfPresent(Bool.self, forKey: .grandOpeningBundle) ?? false
    }
}

/// Login calendar progress. Tracked by calendar day, not by a rolling 24h timer.
struct DailyRewardState: Codable, Equatable {
    var currentDay: Int = 1
    var lastClaimedDay: Date? = nil
    /// Consecutive claim days, independent of the 7-day reward cycle above - it never wraps
    /// back to 1, so long-run milestones (30, 60, 100 days) have something to measure.
    var streakLength: Int = 0
    var claimedStreakMilestones: Set<Int> = []
    /// Spent automatically the next time a day would otherwise be missed.
    var streakFreezes: Int = 0

    enum CodingKeys: String, CodingKey {
        case currentDay, lastClaimedDay, streakLength, claimedStreakMilestones, streakFreezes
    }

    init() {}

    /// Hand-written for the same reason as `GameState`'s: a synthesized decoder throws on
    /// any key an older save doesn't have yet, which would fail decoding this whole struct -
    /// and with it the save's entire `daily` field - the moment a new streak field is added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentDay = try c.decodeIfPresent(Int.self, forKey: .currentDay) ?? 1
        lastClaimedDay = try c.decodeIfPresent(Date.self, forKey: .lastClaimedDay)
        streakLength = try c.decodeIfPresent(Int.self, forKey: .streakLength) ?? 0
        claimedStreakMilestones = try c.decodeIfPresent(Set<Int>.self, forKey: .claimedStreakMilestones) ?? []
        streakFreezes = try c.decodeIfPresent(Int.self, forKey: .streakFreezes) ?? 0
    }
}

struct GameState: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = GameState.currentSchemaVersion
    var coins: Double = 0
    var gems: Int = 25
    /// Spendable stars. Research draws from this balance.
    var stars: Int = 0
    /// Every star ever earned - this is what drives the permanent profit bonus, so spending
    /// stars on research never claws back the multiplier the player already earned.
    var lifetimeStars: Int = 0
    var lifetimeEarnings: Double = 0
    var runEarnings: Double = 0

    var venues: [VenueState] = []
    var currentVenue: Int = 0

    var boosts: [BoostState] = []
    var entitlements = Entitlements()
    var daily = DailyRewardState()

    var lastSeen: Date = Date()
    /// When the free Coffee Break boost comes off cooldown.
    var boostAvailableAt: Date = .distantPast
    /// Start-of-day of the last free welcome-back double, so it is once per day.
    var lastOfflineDoubleDay: Date? = nil
    var timeOffset: TimeInterval = 0

    // Depth systems
    var research: [String: Int] = [:]
    var managers: [OwnedManager] = []
    var recipeCards: [String: Int] = [:]
    var quests: [ActiveQuest] = []
    var questsClaimed: Int = 0
    var festival = FestivalState()
    var league = LeagueState()
    var tutorial = TutorialState()

    // Active play
    var rushEndsAt: Date = .distantPast
    var rushAvailableAt: Date = .distantPast
    var rushesCompleted: Int = 0
    var totalTaps: Int = 0
    var totalServed: Int = 0

    // Achievements
    var errands: [ActiveErrand] = []

    var claimedAchievements: Set<String> = []
    var prestigeCount: Int = 0
    /// Kept separately from `league.tier` because `league` is replaced wholesale every time
    /// a season settles - this is the one thing that has to survive that reassignment.
    var bestLeagueTierReached: LeagueTier = .bronze

    // MARK: New game

    static func newGame() -> GameState {
        var state = GameState()
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        state.venues[0].stations[0].level = 1
        return state
    }

    /// Rebuilds arrays if the catalog grew since the save was written, and completes the
    /// schema-1 manager migration.
    mutating func reconcileWithCatalog() {
        while venues.count < Balance.venues.count {
            let index = venues.count
            venues.append(VenueState.fresh(venue: Balance.venues[index], unlocked: false))
        }
        for (index, venue) in Balance.venues.enumerated() {
            while venues[index].stations.count < venue.stations.count {
                venues[index].stations.append(StationState())
            }
        }
        currentVenue = min(max(0, currentVenue), Balance.venues.count - 1)
        if !venues[currentVenue].unlocked { currentVenue = 0 }
        venues[0].unlocked = true

        migrateLegacyManagers()

        // A save with history belongs to someone who already knows how to play; only a
        // genuinely fresh start should get the guided opening.
        if lifetimeEarnings > 0 || lifetimeStars > 0 { tutorial.finished = true }

        // Pre-schema-2 saves earned stars before they were spendable, so seed both balances.
        if lifetimeStars < stars { lifetimeStars = stars }
    }

    /// Schema 1 stored `hasManager: true`; give each of those stations a real Trainee.
    private mutating func migrateLegacyManagers() {
        for venueIndex in venues.indices {
            for stationIndex in venues[venueIndex].stations.indices {
                var station = venues[venueIndex].stations[stationIndex]
                guard station.hasManager, station.managerID == nil else { continue }
                let manager = OwnedManager.make(ManagerCatalog.traineeID)
                managers.append(manager)
                station.managerID = manager.id
                station.hasManager = false
                venues[venueIndex].stations[stationIndex] = station
            }
        }
    }

    // MARK: Derived

    /// The engine's notion of "now", including any debug skip.
    var now: Date { Date().addingTimeInterval(timeOffset) }

    var activeBoosts: [BoostState] {
        let t = now
        return boosts.filter { $0.isActive(at: t) }
    }

    var researchEffects: ResearchEffects { Research.effects(ranks: research) }

    /// Everything that scales payouts globally: boosts, prestige stars, VIP, and research.
    /// Combo is deliberately excluded - it is transient and lives on the engine.
    var globalMultiplier: Double {
        let boost = activeBoosts.reduce(1.0) { $0 * $1.multiplier }
        return boost
            * Balance.starMultiplier(stars: lifetimeStars)
            * entitlements.profitMultiplier
            * researchEffects.profitMultiplier
    }

    var offlineCapHours: Double {
        (entitlements.vip ? Balance.offlineCapHoursVIP : Balance.offlineCapHours)
            + researchEffects.offlineCapHours
    }

    var offlineEfficiency: Double {
        min(1, Balance.offlineEfficiency + researchEffects.offlineEfficiency)
    }

    func station(_ venue: Int, _ station: Int) -> StationState {
        venues[venue].stations[station]
    }

    // MARK: Managers

    func manager(id: String?) -> OwnedManager? {
        guard let id else { return nil }
        return managers.first { $0.id == id }
    }

    func managerSpec(venue: Int, station: Int) -> ManagerSpec? {
        manager(id: venues[venue].stations[station].managerID)?.spec
    }

    var assignedManagerIDs: Set<String> {
        var ids: Set<String> = []
        for venue in venues {
            for station in venue.stations {
                if let id = station.managerID { ids.insert(id) }
            }
        }
        return ids
    }

    var assignedManagerCount: Int { assignedManagerIDs.count }

    /// Managers currently away on an errand - neither on the bench nor assignable to a
    /// station until they return.
    var erredManagerIDs: Set<String> { Set(errands.map(\.managerID)) }

    var unassignedManagers: [OwnedManager] {
        let assigned = assignedManagerIDs
        let erred = erredManagerIDs
        return managers.filter { !assigned.contains($0.id) && !erred.contains($0.id) }
    }

    /// Where a manager is currently working, if anywhere.
    func assignment(of managerID: String) -> (venue: Int, station: Int)? {
        for (venueIndex, venue) in venues.enumerated() {
            for (stationIndex, station) in venue.stations.enumerated()
            where station.managerID == managerID {
                return (venueIndex, stationIndex)
            }
        }
        return nil
    }

    /// Manager effects for one station: its own manager plus every venue-wide trait in that venue.
    func managerEffects(venue: Int, station: Int) -> ManagerEffects {
        var effects = ManagerEffects()
        for index in venues[venue].stations.indices {
            guard let spec = managerSpec(venue: venue, station: index) else { continue }
            switch spec.trait {
            case .venueProfit, .tapValue, .offlineBonus, .comboRetention:
                effects.apply(spec.trait)          // these lift the whole venue
            default:
                if index == station { effects.apply(spec.trait) }
            }
        }
        return effects
    }

    /// Venue-wide traits only, for readouts that aren't tied to a single station.
    func venueManagerEffects(venue: Int) -> ManagerEffects {
        var effects = ManagerEffects()
        for index in venues[venue].stations.indices {
            guard let spec = managerSpec(venue: venue, station: index) else { continue }
            switch spec.trait {
            case .venueProfit, .tapValue, .offlineBonus, .comboRetention:
                effects.apply(spec.trait)
            default:
                break
            }
        }
        return effects
    }

    // MARK: Rush

    func isRushActive(at date: Date) -> Bool { rushEndsAt > date }
    func rushRemaining(at date: Date) -> TimeInterval { max(0, rushEndsAt.timeIntervalSince(date)) }
    func rushReady(at date: Date) -> Bool { !isRushActive(at: date) && date >= rushAvailableAt }
    func rushCooldownRemaining(at date: Date) -> TimeInterval {
        max(0, rushAvailableAt.timeIntervalSince(date))
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case schemaVersion, coins, gems, stars, lifetimeStars, lifetimeEarnings, runEarnings
        case venues, currentVenue, boosts, entitlements, daily, lastSeen, timeOffset
        // Was the rewarded-ad cooldown before the game went ad-free; the stored key is kept
        // so existing saves still decode.
        case boostAvailableAt = "adAvailableAt"
        case lastOfflineDoubleDay
        case research, managers, recipeCards, quests, questsClaimed, festival, league, tutorial
        case rushEndsAt, rushAvailableAt, rushesCompleted, totalTaps, totalServed
        case claimedAchievements, prestigeCount, bestLeagueTierReached
        case errands
    }

    init() {}

    /// Hand-written so a save written by an older build still loads: synthesized Codable
    /// throws on any missing key, which would silently wipe an existing player's empire.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        coins = try c.decodeIfPresent(Double.self, forKey: .coins) ?? 0
        gems = try c.decodeIfPresent(Int.self, forKey: .gems) ?? 25
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        lifetimeStars = try c.decodeIfPresent(Int.self, forKey: .lifetimeStars) ?? stars
        lifetimeEarnings = try c.decodeIfPresent(Double.self, forKey: .lifetimeEarnings) ?? 0
        runEarnings = try c.decodeIfPresent(Double.self, forKey: .runEarnings) ?? 0

        venues = try c.decodeIfPresent([VenueState].self, forKey: .venues) ?? []
        currentVenue = try c.decodeIfPresent(Int.self, forKey: .currentVenue) ?? 0
        boosts = try c.decodeIfPresent([BoostState].self, forKey: .boosts) ?? []
        entitlements = try c.decodeIfPresent(Entitlements.self, forKey: .entitlements) ?? Entitlements()
        daily = try c.decodeIfPresent(DailyRewardState.self, forKey: .daily) ?? DailyRewardState()
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date()
        boostAvailableAt = try c.decodeIfPresent(Date.self, forKey: .boostAvailableAt) ?? .distantPast
        lastOfflineDoubleDay = try c.decodeIfPresent(Date.self, forKey: .lastOfflineDoubleDay)
        timeOffset = try c.decodeIfPresent(TimeInterval.self, forKey: .timeOffset) ?? 0

        research = try c.decodeIfPresent([String: Int].self, forKey: .research) ?? [:]
        managers = try c.decodeIfPresent([OwnedManager].self, forKey: .managers) ?? []
        recipeCards = try c.decodeIfPresent([String: Int].self, forKey: .recipeCards) ?? [:]
        quests = try c.decodeIfPresent([ActiveQuest].self, forKey: .quests) ?? []
        questsClaimed = try c.decodeIfPresent(Int.self, forKey: .questsClaimed) ?? 0
        festival = try c.decodeIfPresent(FestivalState.self, forKey: .festival) ?? FestivalState()
        league = try c.decodeIfPresent(LeagueState.self, forKey: .league) ?? LeagueState()
        tutorial = try c.decodeIfPresent(TutorialState.self, forKey: .tutorial) ?? TutorialState()

        rushEndsAt = try c.decodeIfPresent(Date.self, forKey: .rushEndsAt) ?? .distantPast
        rushAvailableAt = try c.decodeIfPresent(Date.self, forKey: .rushAvailableAt) ?? .distantPast
        rushesCompleted = try c.decodeIfPresent(Int.self, forKey: .rushesCompleted) ?? 0
        totalTaps = try c.decodeIfPresent(Int.self, forKey: .totalTaps) ?? 0
        totalServed = try c.decodeIfPresent(Int.self, forKey: .totalServed) ?? 0

        claimedAchievements = try c.decodeIfPresent(Set<String>.self, forKey: .claimedAchievements) ?? []
        prestigeCount = try c.decodeIfPresent(Int.self, forKey: .prestigeCount) ?? 0
        bestLeagueTierReached = try c.decodeIfPresent(LeagueTier.self, forKey: .bestLeagueTierReached) ?? .bronze

        errands = try c.decodeIfPresent([ActiveErrand].self, forKey: .errands) ?? []
    }
}
