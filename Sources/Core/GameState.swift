import Foundation

// MARK: - Persisted model

struct StationState: Codable, Equatable {
    var level: Int = 0
    var hasManager: Bool = false
    /// Seconds elapsed into the current cycle. Only meaningful while `isRunning`.
    var elapsed: TimeInterval = 0
    var isRunning: Bool = false

    var isOwned: Bool { level > 0 }
}

struct VenueState: Codable, Equatable {
    var unlocked: Bool = false
    var stations: [StationState] = []

    static func fresh(venue: VenueSpec, unlocked: Bool) -> VenueState {
        VenueState(
            unlocked: unlocked,
            stations: venue.stations.map { _ in StationState() }
        )
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

    /// VIP both pays more and lets the player idle far longer.
    var profitMultiplier: Double { vip ? 1 + Balance.vipProfitBonus : 1 }
    var offlineCapHours: Double { vip ? Balance.offlineCapHoursVIP : Balance.offlineCapHours }
    var adsRemoved: Bool { vip }
}

/// Login calendar progress. Tracked by calendar day, not by a rolling 24h timer, so it
/// behaves the way players expect a "daily" to behave.
struct DailyRewardState: Codable, Equatable {
    /// 1...7, the day the player will claim next.
    var currentDay: Int = 1
    /// Start-of-day for the last successful claim, in the user's calendar.
    var lastClaimedDay: Date? = nil
}

struct GameState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = GameState.currentSchemaVersion
    var coins: Double = 0
    var gems: Int = 25
    var stars: Int = 0
    var lifetimeEarnings: Double = 0
    /// Earnings since the last prestige. Drives the "this run" readout.
    var runEarnings: Double = 0

    var venues: [VenueState] = []
    var currentVenue: Int = 0

    var boosts: [BoostState] = []
    var entitlements = Entitlements()
    var daily = DailyRewardState()

    /// When the app last had the player's attention. Offline income is measured from here.
    var lastSeen: Date = Date()
    var adAvailableAt: Date = .distantPast

    /// Debug-menu clock offset. Persisted so a skip survives a relaunch, which is exactly
    /// what makes offline earnings and daily rewards testable in one sitting.
    var timeOffset: TimeInterval = 0

    // MARK: New game

    static func newGame() -> GameState {
        var state = GameState()
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        // Hand the player a working first station so the very first tap pays out.
        state.venues[0].stations[0].level = 1
        return state
    }

    /// Rebuilds arrays if the catalog grew since the save was written.
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
    }

    // MARK: Derived

    /// The engine's notion of "now", including any debug skip.
    var now: Date { Date().addingTimeInterval(timeOffset) }

    var activeBoosts: [BoostState] {
        let t = now
        return boosts.filter { $0.isActive(at: t) }
    }

    /// Everything that scales payouts: boosts, prestige stars, and VIP.
    var globalMultiplier: Double {
        let boost = activeBoosts.reduce(1.0) { $0 * $1.multiplier }
        return boost * Balance.starMultiplier(stars: stars) * entitlements.profitMultiplier
    }

    func station(_ venue: Int, _ station: Int) -> StationState {
        venues[venue].stations[station]
    }
}
