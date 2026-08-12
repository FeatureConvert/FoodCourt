import Foundation

/// A permanent bonus the player picks when a station crosses a choice milestone. Two players'
/// Fry Baskets can now differ, which is the whole point - the economy had no decisions in it.
enum PerkEffect: Equatable {
    case profit(Double)       // multiplier on payout
    case speed(Double)        // multiplier on cycle rate
    case doubleServe(Double)  // chance to pay twice
    /// Both at once - the specialization tier trades one for the other in a single pick
    /// (Batch Mode: slow and huge; Rapid Fire: fast and lean).
    case tempo(profit: Double, speed: Double)
}

struct Perk: Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
    let symbol: String
    let effect: PerkEffect
}

enum Perks {

    /// The same levels as the auto milestones (see `Balance.milestones`) - hitting one is
    /// already a moment, so that is where the choice belongs. The milestone bonus still
    /// applies on top. Used to include 25 and 50, neither an actual milestone level, which
    /// meant most of a run's four total choices got spent on whichever station happened to
    /// hit 25 first - usually within the opening minutes, on a station picked essentially at
    /// random rather than one the player had actually settled into. Moved to the hundreds
    /// tier so all four choices land on stations worth the commitment, later venues included,
    /// rather than being front-loaded onto day-one picks.
    /// Level 500 is the specialization tier - the picks there change how a station FEELS
    /// (chunky batches, rapid fire, jackpot serves), not just its numbers, so two late-game
    /// boards finally diverge in texture and not only in multipliers.
    static let choiceLevels = [100, 250, 500, 1000]

    static func choices(at level: Int) -> [Perk] {
        switch level {
        case 1000:
            return [
                Perk(id: 0, title: "Legendary Recipe", detail: "+500% profit",
                     symbol: "trophy.fill", effect: .profit(6)),
                Perk(id: 1, title: "Lightning Line", detail: "80% faster cycles",
                     symbol: "bolt.circle.fill", effect: .speed(1 / 0.2)),
                Perk(id: 2, title: "Endless Line", detail: "65% chance to serve twice",
                     symbol: "infinity", effect: .doubleServe(0.65)),
            ]
        case 500:
            return [
                Perk(id: 0, title: "Batch Mode", detail: "×5 cycle time, ×6 payout - big, slow, satisfying servings",
                     symbol: "shippingbox.fill", effect: .tempo(profit: 6, speed: 0.2)),
                Perk(id: 1, title: "Rapid Fire", detail: "Cycles ×2 as fast at 60% payout - floods of serves for goals and tickets",
                     symbol: "bolt.horizontal.fill", effect: .tempo(profit: 0.6, speed: 2)),
                Perk(id: 2, title: "Tip Magnet", detail: "25% chance every serve pays double",
                     symbol: "sparkles", effect: .doubleServe(0.25)),
            ]
        case 250:
            return [
                Perk(id: 0, title: "Master Recipe", detail: "+400% profit",
                     symbol: "crown.fill", effect: .profit(5)),
                Perk(id: 1, title: "Turbo Line", detail: "70% faster cycles",
                     symbol: "wind", effect: .speed(1 / 0.3)),
                Perk(id: 2, title: "Loyal Regulars", detail: "55% chance to serve twice",
                     symbol: "person.3.fill", effect: .doubleServe(0.55)),
            ]
        default: // 100
            return [
                Perk(id: 0, title: "Signature Dish", detail: "+300% profit",
                     symbol: "star.circle.fill", effect: .profit(4)),
                Perk(id: 1, title: "Assembly Line", detail: "60% faster cycles",
                     symbol: "hare.fill", effect: .speed(2.5)),
                Perk(id: 2, title: "Queue Out The Door", detail: "45% chance to serve twice",
                     symbol: "figure.stand.line.dotted.figure.stand", effect: .doubleServe(0.45)),
            ]
        }
    }

    static func perk(at level: Int, index: Int) -> Perk? {
        let options = choices(at: level)
        guard options.indices.contains(index) else { return nil }
        return options[index]
    }

    /// Choice levels the station has reached but not yet spent.
    static func pending(level: Int, chosen: [Int: Int]) -> Int? {
        choiceLevels.first { level >= $0 && chosen[$0] == nil }
    }

    // MARK: Aggregation

    static func profitMultiplier(chosen: [Int: Int]) -> Double {
        aggregate(chosen) {
            switch $0 {
            case .profit(let v): return v
            case .tempo(let profit, _): return profit
            default: return nil
            }
        }
    }

    static func speedMultiplier(chosen: [Int: Int]) -> Double {
        aggregate(chosen) {
            switch $0 {
            case .speed(let v): return v
            case .tempo(_, let speed): return speed
            default: return nil
            }
        }
    }

    /// Chances combine as independent rolls rather than summing past 1.
    static func doubleServeChance(chosen: [Int: Int]) -> Double {
        var missChance = 1.0
        for (level, index) in chosen {
            guard let perk = perk(at: level, index: index),
                  case .doubleServe(let chance) = perk.effect else { continue }
            missChance *= (1 - chance)
        }
        return 1 - missChance
    }

    private static func aggregate(_ chosen: [Int: Int], _ value: (PerkEffect) -> Double?) -> Double {
        var total = 1.0
        for (level, index) in chosen {
            guard let perk = perk(at: level, index: index),
                  let v = value(perk.effect) else { continue }
            total *= v
        }
        return total
    }
}
