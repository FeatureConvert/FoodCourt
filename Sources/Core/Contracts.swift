import Foundation

/// Franchise Contracts: a run modifier picked right after each Franchise reset, so no two
/// runs have to play the same. Every contract is a genuine trade - a buff priced with a
/// debuff - because a strictly-positive pick would just be a stat, not a decision. "Play
/// it straight" is always on offer for players who want the vanilla run.
struct FranchiseContract: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String

    // Effect hooks, all multiplicative/additive into paths that already exist.
    var speedMultiplier: Double = 1        // station cycle rate
    var profitMultiplier: Double = 1       // station payout
    var tapMultiplier: Double = 1
    var comboCapBonus: Int = 0
    var offlineEfficiencyDelta: Double = 0 // added to the 0.5 base
    var offlineCapBonusHours: Double = 0
    var staleGraceDeltaHours: Double = 0   // moves the staleness grace period
    var venueUnlockCostMultiplier: Double = 1
    var starAwardBonus: Double = 0         // fraction added to the NEXT prestige award
}

// MARK: - Catering

/// A daily multi-station order: "the school fair needs 800 fries and 500 sodas by
/// tonight." Fills the mid-term gap between 90-second quests and week-long seasons, and -
/// unlike every other goal - cares about the COMPOSITION of your board: the stations named
/// have to actually be running.
struct CateringOrder: Codable, Equatable {
    /// Day ordinal it was rolled for - one order per day.
    var day: Int
    var venue: Int
    /// Station id -> dishes required.
    var requirements: [Int: Int]
    var progress: [Int: Int] = [:]
    var expiresAt: Date
    var rewardGems: Int
    var rewardIncomeSeconds: Double
    var claimed: Bool = false

    enum CodingKeys: String, CodingKey {
        case day, venue, requirements, progress, expiresAt, rewardGems, rewardIncomeSeconds, claimed
    }

    init(day: Int, venue: Int, requirements: [Int: Int], expiresAt: Date,
         rewardGems: Int, rewardIncomeSeconds: Double) {
        self.day = day
        self.venue = venue
        self.requirements = requirements
        self.expiresAt = expiresAt
        self.rewardGems = rewardGems
        self.rewardIncomeSeconds = rewardIncomeSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? 0
        venue = try c.decodeIfPresent(Int.self, forKey: .venue) ?? 0
        requirements = try c.decodeIfPresent([Int: Int].self, forKey: .requirements) ?? [:]
        progress = try c.decodeIfPresent([Int: Int].self, forKey: .progress) ?? [:]
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt) ?? Date()
        rewardGems = try c.decodeIfPresent(Int.self, forKey: .rewardGems) ?? 0
        rewardIncomeSeconds = try c.decodeIfPresent(Double.self, forKey: .rewardIncomeSeconds) ?? 0
        claimed = try c.decodeIfPresent(Bool.self, forKey: .claimed) ?? false
    }

    var isComplete: Bool {
        requirements.allSatisfy { (progress[$0.key] ?? 0) >= $0.value }
    }

    func fraction(station: Int) -> Double {
        guard let need = requirements[station], need > 0 else { return 0 }
        return min(1, Double(progress[station] ?? 0) / Double(need))
    }
}

enum Catering {

    /// Rolls the day's order against the player's CURRENT venue: two owned stations,
    /// targets sized to a few active-ish hours of each station's own throughput. Returns
    /// nil when the venue can't support one yet (fewer than two owned stations).
    static func roll(day: Int, state: GameState, now: Date) -> CateringOrder? {
        let venue = state.currentVenue
        let owned = Balance.venue(venue).stations.filter { state.venues[venue].stations[$0.id].isOwned }
        guard owned.count >= 2 else { return nil }

        let rng = SeededRandom(seed: day &* 31 &+ venue &* 7)
        var picks: Set<Int> = []
        while picks.count < 2 { picks.insert(owned[rng.next(owned.count)].id) }

        var requirements: [Int: Int] = [:]
        for id in picks {
            let level = state.venues[venue].stations[id].level
            let spec = Balance.venue(venue).stations[id]
            let cycle = max(Balance.minimumCycle, Balance.cycleTime(spec: spec, level: level))
            // ~4 hours of that station's own pace, floored so early boards still get a
            // real ask rather than a freebie.
            requirements[id] = max(150, Int((4 * 3600 / cycle).rounded()))
        }
        return CateringOrder(
            day: day, venue: venue, requirements: requirements,
            expiresAt: now.addingTimeInterval(24 * 3600),
            rewardGems: 25, rewardIncomeSeconds: 900)
    }
}

enum Contracts {

    static let all: [FranchiseContract] = [
        FranchiseContract(
            id: "straight", title: "Play It Straight",
            detail: "No modifiers. The classic run.",
            symbol: "checkmark.seal.fill"),
        FranchiseContract(
            id: "doubletime", title: "Double-Time Crew",
            detail: "Stations cycle ×2 faster, but pay 40% less per serve.",
            symbol: "hare.fill",
            speedMultiplier: 2, profitMultiplier: 0.6),
        FranchiseContract(
            id: "highroller", title: "High Roller",
            detail: "×1.8 profit everywhere - and the staleness tax starts 6 hours sooner.",
            symbol: "flame.fill",
            profitMultiplier: 1.8, staleGraceDeltaHours: -6),
        FranchiseContract(
            id: "opendoors", title: "Open Doors",
            detail: "Venues cost half to unlock, but every serve pays 25% less.",
            symbol: "building.2.fill",
            profitMultiplier: 0.75, venueUnlockCostMultiplier: 0.5),
        FranchiseContract(
            id: "showtime", title: "Showtime",
            detail: "+4 combo steps and ×2 tap value - offline earnings drop to a trickle.",
            symbol: "hand.tap.fill",
            tapMultiplier: 2, comboCapBonus: 4, offlineEfficiencyDelta: -0.35),
        FranchiseContract(
            id: "nightowl", title: "Night Owl",
            detail: "+6h offline cap and full offline rate, but taps are worth half.",
            symbol: "moon.stars.fill",
            tapMultiplier: 0.5, offlineEfficiencyDelta: 0.5, offlineCapBonusHours: 6),
        FranchiseContract(
            id: "showcase", title: "Investor Showcase",
            detail: "Next Franchise pays +20% stars - this whole run earns 25% less.",
            symbol: "star.circle.fill",
            profitMultiplier: 0.75, starAwardBonus: 0.2),
    ]

    private static let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func contract(_ id: String?) -> FranchiseContract? {
        guard let id else { return nil }
        return index[id]
    }

    /// Three options per reset: Play It Straight always leads (the safe pick must never be
    /// hidden behind a reroll), plus two rotating trades seeded by prestige count so the
    /// pair changes every run but is stable across relaunches mid-choice.
    static func offer(prestigeCount: Int) -> [FranchiseContract] {
        let trades = all.filter { $0.id != "straight" }
        let a = trades[prestigeCount % trades.count]
        let b = trades[(prestigeCount + 3) % trades.count]
        let second = (b.id == a.id) ? trades[(prestigeCount + 1) % trades.count] : b
        return [all[0], a, second]
    }
}
