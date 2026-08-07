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

    var profitMultiplier: Double { vip ? 1 + Balance.vipProfitBonus : 1 }
    var adsRemoved: Bool { vip }
}

/// Login calendar progress. Tracked by calendar day, not by a rolling 24h timer.
struct DailyRewardState: Codable, Equatable {
    var currentDay: Int = 1
    var lastClaimedDay: Date? = nil
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
    var adAvailableAt: Date = .distantPast
    var timeOffset: TimeInterval = 0

    // Depth systems
    var research: [String: Int] = [:]
    var managers: [OwnedManager] = []
    var recipeCards: [String: Int] = [:]
    var quests: [ActiveQuest] = []
    var questsClaimed: Int = 0
    var festival = FestivalState()
    var league = LeagueState()

    // Active play
    var rushEndsAt: Date = .distantPast
    var rushAvailableAt: Date = .distantPast
    var rushesCompleted: Int = 0
    var totalTaps: Int = 0
    var totalServed: Int = 0

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

    var unassignedManagers: [OwnedManager] {
        let assigned = assignedManagerIDs
        return managers.filter { !assigned.contains($0.id) }
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
        case venues, currentVenue, boosts, entitlements, daily, lastSeen, adAvailableAt, timeOffset
        case research, managers, recipeCards, quests, questsClaimed, festival, league
        case rushEndsAt, rushAvailableAt, rushesCompleted, totalTaps, totalServed
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
        adAvailableAt = try c.decodeIfPresent(Date.self, forKey: .adAvailableAt) ?? .distantPast
        timeOffset = try c.decodeIfPresent(TimeInterval.self, forKey: .timeOffset) ?? 0

        research = try c.decodeIfPresent([String: Int].self, forKey: .research) ?? [:]
        managers = try c.decodeIfPresent([OwnedManager].self, forKey: .managers) ?? []
        recipeCards = try c.decodeIfPresent([String: Int].self, forKey: .recipeCards) ?? [:]
        quests = try c.decodeIfPresent([ActiveQuest].self, forKey: .quests) ?? []
        questsClaimed = try c.decodeIfPresent(Int.self, forKey: .questsClaimed) ?? 0
        festival = try c.decodeIfPresent(FestivalState.self, forKey: .festival) ?? FestivalState()
        league = try c.decodeIfPresent(LeagueState.self, forKey: .league) ?? LeagueState()

        rushEndsAt = try c.decodeIfPresent(Date.self, forKey: .rushEndsAt) ?? .distantPast
        rushAvailableAt = try c.decodeIfPresent(Date.self, forKey: .rushAvailableAt) ?? .distantPast
        rushesCompleted = try c.decodeIfPresent(Int.self, forKey: .rushesCompleted) ?? 0
        totalTaps = try c.decodeIfPresent(Int.self, forKey: .totalTaps) ?? 0
        totalServed = try c.decodeIfPresent(Int.self, forKey: .totalServed) ?? 0
    }
}
