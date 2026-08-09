import Foundation

/// The Legacy tree: each Legacy level still pays its flat +20% profit (see
/// `Balance.legacyMultiplier`), AND grants one pick from this permanent perk list. Levels
/// stack picks, so two players at Legacy 3 can be genuinely different empires - Legacy
/// becomes a build, not a counter. Picks are forever; that's what "Legacy" means here.
struct LegacyPerk: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let maxStacks: Int
}

enum LegacyTree {

    static let all: [LegacyPerk] = [
        LegacyPerk(id: "capital", title: "Seed Capital",
                   detail: "Every run starts with an hour of income already banked.",
                   symbol: "banknote.fill", maxStacks: 3),
        LegacyPerk(id: "patience", title: "Slow Cooker",
                   detail: "The staleness tax starts 4 hours later, permanently.",
                   symbol: "clock.badge.checkmark", maxStacks: 2),
        LegacyPerk(id: "nightshift", title: "Standing Night Shift",
                   detail: "+4 hours of offline earnings cap, permanently.",
                   symbol: "moon.zzz.fill", maxStacks: 3),
        LegacyPerk(id: "showman", title: "Crowd Favorite",
                   detail: "+2 combo steps, permanently.",
                   symbol: "waveform.path", maxStacks: 2),
        LegacyPerk(id: "negotiator", title: "Master Negotiator",
                   detail: "Every Franchise pays +10% stars, permanently.",
                   symbol: "star.leadinghalf.filled", maxStacks: 2),
    ]

    private static let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func perk(_ id: String) -> LegacyPerk? { index[id] }

    /// Three options per Legacy, excluding anything already at max stacks. Seeded by the
    /// new level so the offer is stable across relaunches mid-choice.
    static func offer(level: Int, taken: [String: Int]) -> [LegacyPerk] {
        let available = all.filter { (taken[$0.id] ?? 0) < $0.maxStacks }
        guard available.count > 3 else { return available }
        var picks: [LegacyPerk] = []
        var cursor = level
        while picks.count < 3 {
            let candidate = available[cursor % available.count]
            if !picks.contains(candidate) { picks.append(candidate) }
            cursor += 1
        }
        return picks
    }

    // MARK: Aggregated effects

    struct Effects: Equatable {
        var startingCapitalHours: Double = 0
        var staleGraceBonusHours: Double = 0
        var offlineCapBonusHours: Double = 0
        var comboCapBonus: Int = 0
        var starAwardBonus: Double = 0
    }

    static func effects(taken: [String: Int]) -> Effects {
        var e = Effects()
        for (id, stacks) in taken {
            let n = Double(min(stacks, perk(id)?.maxStacks ?? 0))
            switch id {
            case "capital":    e.startingCapitalHours += 1 * n
            case "patience":   e.staleGraceBonusHours += 4 * n
            case "nightshift": e.offlineCapBonusHours += 4 * n
            case "showman":    e.comboCapBonus += 2 * Int(n)
            case "negotiator": e.starAwardBonus += 0.10 * n
            default: break
            }
        }
        return e
    }
}
