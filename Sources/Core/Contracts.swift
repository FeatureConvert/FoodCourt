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
