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
    /// The whale-tier permanent: +50% profit and a deeper offline cap, stacking
    /// multiplicatively with VIP rather than replacing it.
    var mogul: Bool = false
    /// One-time flag so `refreshEntitlements`' relaunch redelivery can't re-grant the
    /// Founder's Bundle contents - same pattern as `grandOpeningBundle`.
    var foundersBundle: Bool = false

    var profitMultiplier: Double {
        (vip ? 1 + Balance.vipProfitBonus : 1) * (mogul ? 1 + Balance.mogulProfitBonus : 1)
    }
    /// VIP carries the Carnival Pass, every season, for as long as they hold it.
    var includesFestivalPremium: Bool { vip }

    enum CodingKeys: String, CodingKey {
        case vip, starterPack, grandOpeningBundle, mogul, foundersBundle
    }

    init() {}

    /// Hand-written for the same reason as `GameState`'s: a synthesized decoder throws on
    /// any key an older save doesn't have yet, which would fail the whole save's decode -
    /// not just this one flag - the moment a new entitlement is added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vip = try c.decodeIfPresent(Bool.self, forKey: .vip) ?? false
        starterPack = try c.decodeIfPresent(Bool.self, forKey: .starterPack) ?? false
        grandOpeningBundle = try c.decodeIfPresent(Bool.self, forKey: .grandOpeningBundle) ?? false
        mogul = try c.decodeIfPresent(Bool.self, forKey: .mogul) ?? false
        foundersBundle = try c.decodeIfPresent(Bool.self, forKey: .foundersBundle) ?? false
    }
}

/// Login calendar progress. Tracked by calendar day, not by a rolling 24h timer.
/// The second, much rarer prestige layer. See `GameEngine.legacyReset`.
struct LegacyState: Codable, Equatable {
    var level: Int = 0

    enum CodingKeys: String, CodingKey { case level }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
    }
}

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

    /// When the current board (since the last Franchise or Legacy reset, or the start of a
    /// brand new save) began. Drives `Balance.stalenessMultiplier` - see that doc comment for
    /// why a board's own cost curve needs a second, time-based brake. Old saves decode this as
    /// "right now," which starts them with a full fresh grace period rather than retroactively
    /// taxing a board they were already partway through.
    var boardStartedAt: Date = Date()

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

    /// Venue id -> equipped skin id. A venue with no entry shows "classic", which is always
    /// free and never needs to appear in `unlockedSkins`.
    var venueSkins: [Int: String] = [:]
    /// Venue id -> non-classic skin ids that venue has paid to unlock.
    var unlockedSkins: [Int: Set<String>] = [:]

    var legacy = LegacyState()

    /// `GuestChef.weekKey` of the last successful purchase, so a repurchase can't happen
    /// twice in the same week. Nil for a player who has never bought one.
    var lastGuestChefPurchaseWeek: Int? = nil

    /// `GuestChef.weekKey` of the last time the banner's one-shot celebration played, kept
    /// separate from `lastGuestChefPurchaseWeek` since the spotlight fires on first *sight*
    /// of the week's pick, whether or not the player buys it.
    var lastGuestChefSpotlightWeek: Int? = nil

    var claimedAchievements: Set<String> = []
    var prestigeCount: Int = 0
    /// Stars from the most recent Franchise reset. Deep research ranks are priced as a
    /// fraction of this (`Balance.researchAwardCostFraction`) - fixed per board, unlike
    /// live `pendingStars`, so purchase timing can't game the price. Zeroed by a Legacy
    /// reset so post-Legacy early ranks fall back to the cheap static floor.
    var lastPrestigeAward: Int = 0
    /// Exponents (10^n lifetime earnings) already celebrated - see `GameEngine.landmarkExponents`.
    var landmarksCrossed: Set<Int> = []
    /// Consecutive punctual Rush Hours (started within an hour of cooldown end). Max 3;
    /// each tier past the first adds +25% to the Rush multiplier.
    var rushChain: Int = 0
    /// `totalServed` at the moment the current board began, so the run recap can report
    /// dishes served this franchise rather than lifetime.
    var servedAtBoardStart: Int = 0
    /// Seeds the persistent league nemesis (name + pace), stable for this save's lifetime.
    var nemesisSeed: Int = Int.random(in: 0..<1_000_000)
    /// Venue id -> mastery tier (1 bronze / 2 silver / 3 gold), earned by taking every
    /// station in the venue to Lv 50/100/250. Survives prestige - it's an accomplishment.
    var venueMastery: [Int: Int] = [:]
    /// Highest festival tier ever reached, across all seasons - the personal best.
    var bestFestivalTier: Int = 0
    /// Bond accrual bookkeeping - see `GameEngine.accrueBondTime`.
    var lastBondAccrualAt: Date = Date()
    /// The big weekly challenge - one oversized quest per calendar week with a
    /// premium-feel reward, separate from the three fast slots. Keyed by `GuestChef.weekKey`
    /// so a new one rolls each week whether or not the last was finished.
    var weeklyQuest: ActiveQuest? = nil
    var weeklyQuestWeek: Int? = nil
    /// The Franchise Contract governing this run - nil means "not chosen yet" (the picker
    /// is owed), and the "straight" contract means an explicitly-chosen vanilla run.
    var activeContract: String? = nil
    /// Legacy tree picks: perk id -> stacks taken. Permanent, like everything Legacy.
    var legacyPerks: [String: Int] = [:]
    /// Venue id -> the station crowned as its Signature Dish (x1.5 on that station).
    /// Unlocked by fully 3-starring the venue's recipe set; re-crownable anytime, so it's
    /// a standing strategic knob, not a one-shot. Survives prestige like recipes do.
    var signatureDish: [Int: Int] = [:]
    /// The one in-flight Face-Off, if any - see `Expeditions`.
    var expedition: ActiveExpedition? = nil
    var expeditionWins: Int = 0
    /// Today's catering order - see `Catering`.
    var catering: CateringOrder? = nil
    /// Kitchen tools found so far - permanent, no slots, owning them IS the build.
    var tools: Set<String> = []
    // Weekly Gauntlet - the scored sprint. See `GameEngine.startGauntlet`.
    var gauntletEndsAt: Date? = nil
    var gauntletScore: Double = 0
    var gauntletWeekPlayed: Int? = nil
    var gauntletBestEver: Double = 0
    /// Pinned at sprint start so mid-sprint board changes can't game the purse.
    var gauntletBaseline: Double = 0
    /// `prestigeCount` at the moment of the last Legacy reset - the Legacy gate requires
    /// five NEW franchises since then, or the gate never re-locks (prestigeCount alone
    /// made a second Legacy free the instant the first finished: everything it would wipe
    /// was already zero, so it granted +20% and a perk for nothing, infinitely).
    var prestigeCountAtLegacy: Int = 0
    /// Interactive perk choices spent this franchise run (see `Balance.perkChoicesPerRun`).
    /// Milestones past the cap still pay their automatic speed/profit bonuses - what runs
    /// out is the CHOICE, which turns "which four stations get a build?" into a real
    /// per-run decision instead of a hundred interrupting sheets.
    var perkChoicesUsed: Int = 0

    /// Keys of one-shot explainer moments the player has already seen - the welcome screen,
    /// the first-prestige and first-legacy alerts, the perk primer, and the first-open banner
    /// on each depth tab. A set of freeform strings rather than an enum so a new explainer can
    /// be added later without a schema migration.
    var seenIntros: Set<String> = []
    /// Kept separately from `league.tier` because `league` is replaced wholesale every time
    /// a season settles - this is the one thing that has to survive that reassignment.
    var bestLeagueTierReached: LeagueTier = .bronze

    /// Whether the once-ever free first manager (see `GameEngine.eligibleForFreeFirstManager`)
    /// has already been granted. Deliberately its own flag rather than reusing
    /// `tutorial.step`: `TutorialState.complete(_:)` no-ops entirely once `finished` is true
    /// (via a normal finish OR `skip()`), so a player who dismisses the tutorial before ever
    /// hiring would leave `step` frozen below the hire-manager step forever - which would
    /// keep re-granting a free manager after every future Franchise reset.
    var freeFirstManagerClaimed: Bool = false

    // MARK: New game

    static func newGame() -> GameState {
        var state = GameState()
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        state.venues[0].stations[0].level = 1
        // Coffee Break and Rush Hour otherwise default to instantly ready (the property
        // declaration's .distantPast also serves as the decode-fallback for old saves, so it
        // stays untouched) - a brand-new player stacking both plus max combo in the opening
        // seconds is what let venue 2 fall in under a minute. Lock both out for the first 15
        // minutes of a fresh save specifically.
        let firstBoostAt = state.now.addingTimeInterval(15 * 60)
        state.boostAvailableAt = firstBoostAt
        state.rushAvailableAt = firstBoostAt
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

    /// True during the fixed daily Happy Hour window (see `ActivePlay.happyHourStartHour`).
    /// Live payouts and golden odds only - offline math ignores it on purpose, both to keep
    /// `automatedRate` stable and because the whole point is being present for it.
    func isHappyHour(calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= ActivePlay.happyHourStartHour && hour < ActivePlay.happyHourEndHour
    }

    var activeBoosts: [BoostState] {
        let t = now
        return boosts.filter { $0.isActive(at: t) }
    }

    var researchEffects: ResearchEffects { Research.effects(ranks: research) }
    var contract: FranchiseContract? { Contracts.contract(activeContract) }
    var legacyEffects: LegacyTree.Effects { LegacyTree.effects(taken: legacyPerks) }
    var toolEffects: Tools.Effects { Tools.effects(owned: tools) }

    /// Everything that scales payouts globally: boosts, prestige stars, VIP, and research.
    /// Combo is deliberately excluded - it is transient and lives on the engine.
    var globalMultiplier: Double {
        let boost = activeBoosts.reduce(1.0) { $0 * $1.multiplier }
        return boost
            * Balance.starMultiplier(stars: lifetimeStars)
            * Balance.legacyMultiplier(level: legacy.level)
            * entitlements.profitMultiplier
            * researchEffects.profitMultiplier
            * toolEffects.profitMultiplier
    }

    var offlineCapHours: Double {
        (entitlements.vip ? Balance.offlineCapHoursVIP : Balance.offlineCapHours)
            + (entitlements.mogul ? Balance.mogulOfflineCapBonusHours : 0)
            + researchEffects.offlineCapHours
            + (contract?.offlineCapBonusHours ?? 0)
            + legacyEffects.offlineCapBonusHours
    }

    var offlineEfficiency: Double {
        // Floor at 5%: a contract debuff can make offline a trickle, never literally zero.
        min(1, max(0.05, Balance.offlineEfficiency + researchEffects.offlineEfficiency
                    + (contract?.offlineEfficiencyDelta ?? 0)
                    + Festival.modifier(seasonID: festival.seasonID).offlineEfficiencyBonus
                    + toolEffects.offlineEfficiencyBonus))
    }

    // MARK: Cosmetics

    func skin(venue: Int) -> String { venueSkins[venue] ?? "classic" }

    func hasUnlockedSkin(venue: Int, skin: String) -> Bool {
        skin == "classic" || (unlockedSkins[venue]?.contains(skin) ?? false)
    }

    // MARK: Managers

    func manager(id: String?) -> OwnedManager? {
        guard let id else { return nil }
        return managers.first { $0.id == id }
    }

    func managerSpec(venue: Int, station: Int) -> ManagerSpec? {
        manager(id: venues[venue].stations[station].managerID)?.spec
    }

    func stationManager(venue: Int, station: Int) -> OwnedManager? {
        manager(id: venues[venue].stations[station].managerID)
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

    /// Managers currently away on an errand or a Face-Off - neither on the bench nor
    /// assignable to a station until they return.
    var erredManagerIDs: Set<String> {
        Set(errands.map(\.managerID)).union(expedition?.managerIDs ?? [])
    }

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

    /// Spec ids of everyone staffed in a venue - what synergy detection runs on.
    func staffedSpecIDs(venue: Int) -> Set<String> {
        var ids: Set<String> = []
        for index in venues[venue].stations.indices {
            if let spec = managerSpec(venue: venue, station: index) { ids.insert(spec.id) }
        }
        return ids
    }

    /// Crews fully assembled in this venue right now - see `Synergies`.
    func activeSynergies(venue: Int) -> [ManagerSynergy] {
        Synergies.active(in: staffedSpecIDs(venue: venue))
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
        case claimedAchievements, prestigeCount, bestLeagueTierReached, seenIntros
        case lastPrestigeAward, landmarksCrossed, rushChain, servedAtBoardStart
        case nemesisSeed, venueMastery, bestFestivalTier, lastBondAccrualAt
        case weeklyQuest, weeklyQuestWeek
        case activeContract, legacyPerks, signatureDish, expedition, expeditionWins, catering
        case perkChoicesUsed, tools, prestigeCountAtLegacy
        case gauntletEndsAt, gauntletScore, gauntletWeekPlayed, gauntletBestEver
        case gauntletBaseline
        case boardStartedAt
        case errands
        case venueSkins, unlockedSkins
        case legacy
        case lastGuestChefPurchaseWeek, lastGuestChefSpotlightWeek
        case freeFirstManagerClaimed
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

        // One-time repair for a save corrupted by the since-fixed star-multiplier runaway -
        // see `Balance.maxSaneLifetimeStars`. A legitimate save can never actually cross
        // that ceiling, so this only ever touches a save that already got hit by the bug;
        // everyone else decodes through untouched. Without also capping `lifetimeEarnings`
        // here, the very next prestige would just recompute an equally absurd star award
        // from the still-corrupted total and undo the repair immediately.
        if lifetimeStars > Balance.maxSaneLifetimeStars || lifetimeEarnings > Balance.maxSaneLifetimeEarnings {
            lifetimeStars = min(lifetimeStars, Balance.maxSaneLifetimeStars)
            lifetimeEarnings = min(lifetimeEarnings, Balance.maxSaneLifetimeEarnings)
            stars = min(stars, lifetimeStars)
        }

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
        // Old saves decode as 0: their next research purchases sit on the static floor
        // until the first post-update Franchise records a real award. Cheap for a board or
        // two, never wrong.
        lastPrestigeAward = try c.decodeIfPresent(Int.self, forKey: .lastPrestigeAward) ?? 0
        rushChain = try c.decodeIfPresent(Int.self, forKey: .rushChain) ?? 0
        servedAtBoardStart = try c.decodeIfPresent(Int.self, forKey: .servedAtBoardStart) ?? 0
        nemesisSeed = try c.decodeIfPresent(Int.self, forKey: .nemesisSeed)
            ?? Int.random(in: 0..<1_000_000)
        venueMastery = try c.decodeIfPresent([Int: Int].self, forKey: .venueMastery) ?? [:]
        bestFestivalTier = try c.decodeIfPresent(Int.self, forKey: .bestFestivalTier) ?? 0
        lastBondAccrualAt = try c.decodeIfPresent(Date.self, forKey: .lastBondAccrualAt) ?? Date()
        weeklyQuest = try c.decodeIfPresent(ActiveQuest.self, forKey: .weeklyQuest)
        weeklyQuestWeek = try c.decodeIfPresent(Int.self, forKey: .weeklyQuestWeek)
        // An ABSENT key means a pre-contract-era save: mid-run veterans default to the
        // vanilla contract rather than being owed a pick. A live owed-pick save encodes
        // the explicit "unchosen" sentinel (see Contracts.unchosenID), so it survives
        // relaunch - nil here only ever means "never prestiged".
        activeContract = try c.decodeIfPresent(String.self, forKey: .activeContract)
            ?? (prestigeCount > 0 ? "straight" : nil)
        legacyPerks = try c.decodeIfPresent([String: Int].self, forKey: .legacyPerks) ?? [:]
        signatureDish = try c.decodeIfPresent([Int: Int].self, forKey: .signatureDish) ?? [:]
        expedition = try c.decodeIfPresent(ActiveExpedition.self, forKey: .expedition)
        expeditionWins = try c.decodeIfPresent(Int.self, forKey: .expeditionWins) ?? 0
        catering = try c.decodeIfPresent(CateringOrder.self, forKey: .catering)
        perkChoicesUsed = try c.decodeIfPresent(Int.self, forKey: .perkChoicesUsed) ?? 0
        // Old saves with existing Legacy levels approximate: assume the gate's worth of
        // franchises preceded each level, so they aren't instantly re-eligible on update.
        prestigeCountAtLegacy = try c.decodeIfPresent(Int.self, forKey: .prestigeCountAtLegacy) ?? 0
        tools = try c.decodeIfPresent(Set<String>.self, forKey: .tools) ?? []
        gauntletEndsAt = try c.decodeIfPresent(Date.self, forKey: .gauntletEndsAt)
        gauntletScore = try c.decodeIfPresent(Double.self, forKey: .gauntletScore) ?? 0
        gauntletWeekPlayed = try c.decodeIfPresent(Int.self, forKey: .gauntletWeekPlayed)
        gauntletBestEver = try c.decodeIfPresent(Double.self, forKey: .gauntletBestEver) ?? 0
        gauntletBaseline = try c.decodeIfPresent(Double.self, forKey: .gauntletBaseline) ?? 0
        if let crossed = try c.decodeIfPresent(Set<Int>.self, forKey: .landmarksCrossed) {
            landmarksCrossed = crossed
        } else {
            // Backfill for saves from before landmarks existed: silently mark everything
            // already passed as celebrated, so a veteran doesn't get a confetti barrage.
            landmarksCrossed = Set(GameEngine.landmarkExponents.filter {
                lifetimeEarnings >= pow(10, Double($0))
            })
        }
        bestLeagueTierReached = try c.decodeIfPresent(LeagueTier.self, forKey: .bestLeagueTierReached) ?? .bronze
        // An absent key means a save from before this flag existed. Anyone with history
        // (a manager already hired, or any earnings/stars) already got their free hire under
        // the old tutorial-gated system one way or another - default them to "claimed" so an
        // established save doesn't surface a surprise free manager after its next prestige.
        // A genuinely brand-new save with none of that still correctly defaults to false.
        freeFirstManagerClaimed = try c.decodeIfPresent(Bool.self, forKey: .freeFirstManagerClaimed)
            ?? (!managers.isEmpty || lifetimeEarnings > 0 || lifetimeStars > 0)

        errands = try c.decodeIfPresent([ActiveErrand].self, forKey: .errands) ?? []

        venueSkins = try c.decodeIfPresent([Int: String].self, forKey: .venueSkins) ?? [:]
        unlockedSkins = try c.decodeIfPresent([Int: Set<String>].self, forKey: .unlockedSkins) ?? [:]

        legacy = try c.decodeIfPresent(LegacyState.self, forKey: .legacy) ?? LegacyState()
        lastGuestChefPurchaseWeek = try c.decodeIfPresent(Int.self, forKey: .lastGuestChefPurchaseWeek)
        lastGuestChefSpotlightWeek = try c.decodeIfPresent(Int.self, forKey: .lastGuestChefSpotlightWeek)
        // Missing key means a save from before the staleness tax existed - treat its board as
        // freshly started rather than backdating a tax onto progress the player already made.
        boardStartedAt = try c.decodeIfPresent(Date.self, forKey: .boardStartedAt) ?? Date()

        if let decoded = try c.decodeIfPresent(Set<String>.self, forKey: .seenIntros) {
            seenIntros = decoded
        } else if prestigeCount > 0 || totalTaps > 0 || tutorial.finished {
            // A save from before the onboarding explainers existed. This player has already
            // played - possibly for months - so backfill every explainer as seen rather than
            // greeting a veteran with a "welcome, here's how prestige works" wall on their
            // next launch. A save with none of those signals is indistinguishable from brand
            // new, so it gets the real onboarding flow instead.
            seenIntros = Set(IntroKey.allKeys)
        }
    }
}

/// Freeform keys for one-shot onboarding explainers, shared between `GameState.seenIntros`
/// and the UI views that check/mark them.
enum IntroKey {
    static let welcome = "welcome"
    static let prestige = "prestige"
    static let legacy = "legacy"
    static let perks = "perks"
    static let research = "research"
    static let league = "league"
    static let festival = "festival"
    static let staff = "staff"
    static let recipes = "recipes"
    static let errands = "errands"
    static let cosmetics = "cosmetics"
    static let roadmap = "roadmap"
    /// One-shot toast when a first-run player crosses halfway to their first Franchise -
    /// the moment the "real game" is close enough to be worth naming.
    static let halfwayFranchise = "halfwayFranchise"
    static let guestChef = "guestChef"
    static let icloudSync = "icloudSync"
    static let contracts = "contracts"
    static let legacyTree = "legacyTree"
    static let signature = "signature"
    static let synergies = "synergies"
    static let seasonTwist = "seasonTwist"
    static let expeditions = "expeditions"
    static let catering = "catering"
    static let tools = "tools"
    static let gauntlet = "gauntlet"
    // One-shot "New: X unlocked" toasts fired the moment a pacing gate opens mid-play
    // (the in-tab banners still do the explaining; these just point at the tab).
    /// Graduation beat when the coach-card tutorial finishes, and the first-time pulse on
    /// the Venues tab when the second venue becomes affordable - the two seams the guided
    /// opening used to fall silent across.
    static let tutorialDone = "tutorialDone"
    static let venueNudge = "venueNudge"
    static let crewsUnlockToast = "crewsUnlockToast"
    static let faceOffsUnlockToast = "faceOffsUnlockToast"
    static let gauntletUnlockToast = "gauntletUnlockToast"
    static let toolsUnlockToast = "toolsUnlockToast"

    // One-shot explainers for the "Claim All"/"Buy All"/"Auto-assign" bulk-action buttons -
    // each only ever appears alongside the button itself (gated on the same "more than one
    // thing ready" condition), so a player who never has a backlog never sees it either.
    static let claimAllQuests = "claimAllQuests"
    static let claimAllAchievements = "claimAllAchievements"
    static let claimAllErrandsIntro = "claimAllErrandsIntro"
    static let autoAssignStaff = "autoAssignStaff"
    static let claimAllFestivalIntro = "claimAllFestivalIntro"
    static let buyAllResearch = "buyAllResearch"

    static let allKeys: [String] = [
        welcome, prestige, legacy, perks, research, league, festival, staff, recipes, errands,
        cosmetics, roadmap, halfwayFranchise, guestChef, icloudSync, contracts, legacyTree,
        signature, synergies, seasonTwist, expeditions, catering, tools, gauntlet,
        crewsUnlockToast, faceOffsUnlockToast, gauntletUnlockToast, toolsUnlockToast,
        tutorialDone, venueNudge,
        claimAllQuests, claimAllAchievements, claimAllErrandsIntro, autoAssignStaff,
        claimAllFestivalIntro, buyAllResearch,
    ]
}
