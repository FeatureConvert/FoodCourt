import Foundation

enum QuestKind: String, Codable, CaseIterable {
    case serve, earn, level, hire, tap, rush, recipes

    /// Absolute kinds read a running total rather than accumulating deltas, so they stay
    /// correct even if the app is relaunched mid-quest. A kind must be consistently one or
    /// the other: mixing them makes the target mean something different to the progress.
    var isAbsolute: Bool {
        switch self {
        case .level, .recipes, .hire: return true
        default: return false
        }
    }

    var symbol: String {
        switch self {
        case .serve:   return "takeoutbag.and.cup.and.straw.fill"
        case .earn:    return "dollarsign.circle.fill"
        case .level:   return "chart.line.uptrend.xyaxis"
        case .hire:    return "person.fill.badge.plus"
        case .tap:     return "hand.tap.fill"
        case .rush:    return "timer"
        case .recipes: return "book.closed.fill"
        }
    }
}

struct ActiveQuest: Codable, Equatable, Identifiable {
    var id: String
    var kind: QuestKind
    var target: Double
    var progress: Double
    var rewardGems: Int
    /// Coins are paid as N seconds of current income, so the reward stays relevant late.
    var rewardSeconds: Double

    var isComplete: Bool { progress >= target }
    var fraction: Double { target > 0 ? min(1, progress / target) : 0 }

    var title: String {
        let n = Int(target)
        switch kind {
        case .serve:   return "Serve \(Format.plural(n, "dish", "dishes"))"
        case .earn:    return "Earn \(Format.currency(target)) this run"
        case .level:   return "Take a station to Lv \(Format.count(n))"
        // Absolute kinds describe the end state rather than the action, because progress
        // starts from whatever the player already has.
        case .hire:    return "Staff \(Format.plural(n, "station"))"
        case .tap:     return "Tap \(Format.plural(n, "time"))"
        case .rush:    return "Complete \(Format.plural(n, "Rush Hour"))"
        case .recipes: return "Collect \(Format.plural(n, "recipe card"))"
        }
    }

    var progressLabel: String {
        let shown = min(progress, target)
        switch kind {
        case .earn: return "\(Format.currency(shown)) / \(Format.currency(target))"
        default:    return "\(Format.count(Int(shown))) / \(Format.count(Int(target)))"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, target, progress, rewardGems, rewardSeconds
    }

    init(id: String, kind: QuestKind, target: Double, progress: Double,
         rewardGems: Int, rewardSeconds: Double) {
        self.id = id
        self.kind = kind
        self.target = target
        self.progress = progress
        self.rewardGems = rewardGems
        self.rewardSeconds = rewardSeconds
    }

    /// Hand-written for the same reason as every other persisted state in this save: a
    /// synthesized decoder throws on any key an older save doesn't have, which would corrupt
    /// the whole save the moment a new field ships. No field here has a natural "unset"
    /// default, so a missing/corrupt quest decodes as permanently unfinishable (`target` above
    /// any real `progress` can reach) rather than guessing at values that might hand out a
    /// free claim - the safe direction to err is toward nothing claimable, not a completed
    /// quest with no explanation. `Quests.refill` naturally replaces it on the next slot check.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try c.decodeIfPresent(QuestKind.self, forKey: .kind) ?? .serve
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        target = try c.decodeIfPresent(Double.self, forKey: .target) ?? (progress + 1)
        rewardGems = try c.decodeIfPresent(Int.self, forKey: .rewardGems) ?? 0
        rewardSeconds = try c.decodeIfPresent(Double.self, forKey: .rewardSeconds) ?? 0
    }
}

enum Quests {

    static let slots = 3

    /// Rolls a quest scaled to where the player actually is, so slots never ask for something
    /// trivially done or hopelessly far away.
    static func roll(state: GameState, incomePerSecond: Double,
                     avoiding taken: [QuestKind], seed: Int) -> ActiveQuest {
        var pool = QuestKind.allCases.filter { !taken.contains($0) }
        if pool.isEmpty { pool = QuestKind.allCases }

        let rng = SeededRandom(seed: seed)
        let kind = pool[rng.next(pool.count)]
        let bestLevel = highestStationLevel(state)
        let totalCards = Recipes.totalCollected(state.recipeCards)

        var target: Double
        var gems: Int
        var seconds: Double

        // Quests refill the instant one is claimed, so of every free gem source in the game
        // this is the one a player can farm fastest - three slots cycling continuously add up
        // to real money's worth of gems an hour at the original values. Halved once, then
        // trimmed another ~35% in the August review: an aggregate weekly ledger showed this
        // slot-cycling alone still paid more than every other post-nerf source combined and
        // let a diligent player afford the entire weekly sink menu with room to spare.
        switch kind {
        case .serve:
            // Scaled to current throughput like .earn is, rather than a flat count - a fixed
            // 40-190 target completed almost instantly once several stations were staffed
            // and running fast, since it never accounted for how many dishes/second that is.
            let base = max(40, state.automatedServeRate * 90)
            target = (base * Double(1 + rng.next(3))).rounded()
            gems = 3; seconds = 60
        case .earn:
            // Relative to now, not to the run so far - progress counts from zero, so adding
            // runEarnings here would quietly demand the whole run again.
            let base = max(1_000, incomePerSecond * 120)
            target = base * Double(1 + rng.next(3))
            gems = 5; seconds = 120
        case .level:
            // Always a step beyond the current best, rounded to something legible.
            let step = [5, 10, 25].map { $0 }[rng.next(3)]
            target = Double(((bestLevel / step) + 1) * step)
            gems = 7; seconds = 90
        case .hire:
            target = Double(state.assignedManagerCount + 1 + rng.next(2))
            gems = 8; seconds = 120
        case .tap:
            target = Double(30 + rng.next(6) * 20)
            gems = 3; seconds = 45
        case .rush:
            target = Double(1 + rng.next(2))
            gems = 10; seconds = 180
        case .recipes:
            target = Double(totalCards + 1 + rng.next(2))
            gems = 7; seconds = 90
        }

        var quest = ActiveQuest(
            id: UUID().uuidString, kind: kind, target: target, progress: 0,
            rewardGems: gems, rewardSeconds: seconds
        )
        // Absolute kinds start from wherever the player already is, so the bar shows the
        // distance still to go rather than jumping when the first one lands.
        switch kind {
        case .level:   quest.progress = Double(bestLevel)
        case .recipes: quest.progress = Double(totalCards)
        case .hire:    quest.progress = Double(state.assignedManagerCount)
        default:       break
        }
        return quest
    }

    static func highestStationLevel(_ state: GameState) -> Int {
        var best = 0
        for venue in Balance.venues where state.venues[venue.id].unlocked {
            for station in state.venues[venue.id].stations {
                best = max(best, station.level)
            }
        }
        return best
    }

    /// Refills empty slots without ever handing out two of the same kind at once.
    static func refill(state: inout GameState, incomePerSecond: Double) {
        var guardCount = 0
        while state.quests.count < slots && guardCount < 12 {
            guardCount += 1
            let taken = state.quests.map(\.kind)
            let quest = roll(state: state, incomePerSecond: incomePerSecond,
                             avoiding: taken, seed: Int.random(in: 0..<1_000_000))
            state.quests.append(quest)
        }
    }
}
