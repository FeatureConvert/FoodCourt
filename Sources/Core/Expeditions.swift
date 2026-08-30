import Foundation

/// Food Court Face-Offs: send three benched managers to out-cook a rival crew. Extends the
/// errand timer pattern (pick people, wait, collect) into a light strategy layer - WHO you
/// send matters (rarity + bond), the stake tier is a real risk knob, and the rival is your
/// league nemesis's crew, so the feud finally has a second front.
struct ActiveExpedition: Codable, Equatable {
    var managerIDs: [String]
    var startedAt: Date
    var duration: TimeInterval
    var tier: String            // ExpeditionTier id
    /// Rolled at start so the outcome is fixed the moment the crew leaves - reconnecting
    /// or relaunching can't reroll a loss into a win.
    var roll: Double

    enum CodingKeys: String, CodingKey { case managerIDs, startedAt, duration, tier, roll }

    init(managerIDs: [String], startedAt: Date, duration: TimeInterval, tier: String, roll: Double) {
        self.managerIDs = managerIDs
        self.startedAt = startedAt
        self.duration = duration
        self.tier = tier
        self.roll = roll
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        managerIDs = try c.decodeIfPresent([String].self, forKey: .managerIDs) ?? []
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        tier = try c.decodeIfPresent(String.self, forKey: .tier) ?? "friendly"
        roll = try c.decodeIfPresent(Double.self, forKey: .roll) ?? 0.5
    }

    func isComplete(at date: Date) -> Bool { date >= startedAt.addingTimeInterval(duration) }
    func remaining(at date: Date) -> TimeInterval {
        max(0, startedAt.addingTimeInterval(duration).timeIntervalSince(date))
    }
}

struct ExpeditionTier: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    /// Crew score needed for a guaranteed win; below it, the shortfall becomes loss odds.
    let difficulty: Double
    let hours: Double
    let rewardGems: Int
    /// Coins as hours of income, paid on a win.
    let rewardIncomeHours: Double
    /// Legendary-tier face-offs can bring home an Epic recruit on a win.
    let recruitChance: Double
}

enum Expeditions {

    static let crewSize = 3

    // Rewards raised ~4x (Aug 30 review) against the balance pass's own math: even a
    // best-case, guaranteed-win, maxed-legendary crew was earning roughly 0.7-1.1
    // gems/manager-hour here, against Errands' guaranteed, riskless 7/manager-hour for
    // the same rarity - Face-Offs cost 3x the managers and can still lose, so paying
    // LESS per manager-hour than the safe option had it backwards. At 4x, the same
    // best-case math comes out to ~2.7-4.4 gems/manager-hour: still below Errands'
    // guaranteed rate (a Face-Off is meant to be the bigger swing, not strictly better),
    // but no longer such a wide gap that Errands strictly dominate. The coin side (paid
    // as hours of FULL income on a win, vs Errands' hours at HALF income) moves the same
    // way: friendly/district/grand now pay ~0.33/0.5/0.67x an hour of income per
    // manager-hour committed, up from ~0.08/0.13/0.17x, bracketing Errands' flat 0.5x
    // instead of sitting well under it at every tier. Loss payouts (1/4 of these) and
    // Grand's recruit chance are unchanged - only found to be underpriced, not the odds.
    static let tiers: [ExpeditionTier] = [
        ExpeditionTier(id: "friendly", title: "Friendly Face-Off",
                       detail: "Low stakes, guaranteed experience. 4 hours.",
                       difficulty: 4, hours: 4, rewardGems: 32, rewardIncomeHours: 4,
                       recruitChance: 0),
        ExpeditionTier(id: "district", title: "District Cook-Off",
                       detail: "A real fight. Bring your good people. 8 hours.",
                       difficulty: 9, hours: 8, rewardGems: 80, rewardIncomeHours: 12,
                       recruitChance: 0),
        ExpeditionTier(id: "grand", title: "Grand Face-Off",
                       detail: "The rival's best crew. Winners come home famous. 12 hours.",
                       difficulty: 15, hours: 12, rewardGems: 160, rewardIncomeHours: 24,
                       recruitChance: 0.25),
    ]

    static func tier(_ id: String) -> ExpeditionTier {
        tiers.first { $0.id == id } ?? tiers[0]
    }

    /// A manager's contribution: rarity is most of it, long service (bond) tips fights.
    static func crewScore(_ managers: [OwnedManager]) -> Double {
        managers.reduce(0) { total, manager in
            let rarity: Double
            switch manager.spec.rarity {
            case .common: rarity = 1
            case .rare: rarity = 2
            case .epic: rarity = 3.5
            case .legendary: rarity = 5
            }
            return total + rarity + 0.4 * Double(manager.bondLevel)
        }
    }

    /// Win odds for a crew against a tier: at-or-above difficulty is a lock, and every
    /// point short costs 15%. Shown to the player BEFORE they commit - informed risk is
    /// the fun kind.
    static func winChance(score: Double, tier: ExpeditionTier) -> Double {
        min(1, max(0.1, 1 - max(0, tier.difficulty - score) * 0.15))
    }

    static func isWin(_ expedition: ActiveExpedition, managers: [OwnedManager]) -> Bool {
        let crew = managers.filter { expedition.managerIDs.contains($0.id) }
        let chance = winChance(score: crewScore(crew), tier: tier(expedition.tier))
        return expedition.roll < chance
    }
}
