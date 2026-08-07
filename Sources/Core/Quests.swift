import Foundation

enum QuestKind: String, Codable, CaseIterable {
    case serve, earn, level, hire, tap, rush, recipes

    /// Absolute kinds read a running total rather than accumulating deltas, so they stay
    /// correct even if the app is relaunched mid-quest.
    var isAbsolute: Bool {
        switch self {
        case .level, .recipes: return true
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
        switch kind {
        case .serve:   return "Serve \(Format.count(Int(target))) dishes"
        case .earn:    return "Earn \(Format.currency(target)) this run"
        case .level:   return "Take a station to Lv \(Format.count(Int(target)))"
        case .hire:    return "Hire \(Format.count(Int(target))) managers"
        case .tap:     return "Tap \(Format.count(Int(target))) times"
        case .rush:    return "Complete \(Format.count(Int(target))) Rush Hours"
        case .recipes: return "Collect \(Format.count(Int(target))) recipe cards"
        }
    }

    var progressLabel: String {
        switch kind {
        case .earn: return "\(Format.currency(progress)) / \(Format.currency(target))"
        default:    return "\(Format.count(Int(progress))) / \(Format.count(Int(target)))"
        }
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

        switch kind {
        case .serve:
            target = Double(40 + rng.next(5) * 30)
            gems = 10; seconds = 60
        case .earn:
            let base = max(1_000, incomePerSecond * 120)
            target = state.runEarnings + base * Double(1 + rng.next(3))
            gems = 15; seconds = 120
        case .level:
            // Always a step beyond the current best, rounded to something legible.
            let step = [5, 10, 25].map { $0 }[rng.next(3)]
            target = Double(((bestLevel / step) + 1) * step)
            gems = 20; seconds = 90
        case .hire:
            target = Double(state.assignedManagerCount + 1 + rng.next(2))
            gems = 25; seconds = 120
        case .tap:
            target = Double(30 + rng.next(6) * 20)
            gems = 8; seconds = 45
        case .rush:
            target = Double(1 + rng.next(2))
            gems = 30; seconds = 180
        case .recipes:
            target = Double(totalCards + 1 + rng.next(2))
            gems = 20; seconds = 90
        }

        var quest = ActiveQuest(
            id: UUID().uuidString, kind: kind, target: target, progress: 0,
            rewardGems: gems, rewardSeconds: seconds
        )
        if kind.isAbsolute {
            quest.progress = kind == .level ? Double(bestLevel) : Double(totalCards)
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
