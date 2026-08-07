import Foundation

enum LeagueTier: Int, CaseIterable, Codable, Identifiable {
    case bronze, silver, gold, diamond
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .diamond: return "Diamond"
        }
    }
    var hex: String {
        switch self {
        case .bronze: return "#C88A4A"
        case .silver: return "#C7CBD1"
        case .gold: return "#F0C24B"
        case .diamond: return "#7FD8E8"
        }
    }
    /// Rivals get tougher as you climb, which is what stops the top tier being a formality.
    var rivalStrength: Double {
        switch self {
        case .bronze: return 0.55
        case .silver: return 0.8
        case .gold: return 1.05
        case .diamond: return 1.35
        }
    }
    var gemReward: Int {
        switch self {
        case .bronze: return 25
        case .silver: return 50
        case .gold: return 100
        case .diamond: return 175
        }
    }
}

struct LeagueRival: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    /// Coins per second this rival "earns", fixed when the week is seeded.
    var rate: Double
    var score: Double
}

struct LeagueEntry: Identifiable, Equatable {
    let id: Int
    let name: String
    let score: Double
    let isPlayer: Bool
    let rank: Int
}

enum LeagueOutcome: Equatable {
    case promoted(from: LeagueTier, to: LeagueTier, rank: Int, gems: Int)
    case held(tier: LeagueTier, rank: Int, gems: Int)
    case relegated(from: LeagueTier, to: LeagueTier, rank: Int)

    var headline: String {
        switch self {
        case .promoted(_, let to, _, _): return "Promoted to \(to.name)!"
        case .held(let tier, let rank, _): return "Finished #\(rank) in \(tier.name)"
        case .relegated(_, let to, let rank): return "Relegated to \(to.name) (#\(rank))"
        }
    }
}

struct LeagueState: Codable, Equatable {
    var tier: LeagueTier = .bronze
    var score: Double = 0
    var rivals: [LeagueRival] = []
    var startedAt: Date = Date()
    var endsAt: Date = Date().addingTimeInterval(League.weekLength)
    var lastSettledAt: Date = Date()
    var seasonsPlayed: Int = 0
}

enum League {

    static let size = 30
    static let promoteCount = 7
    static let relegateCount = 7
    static let weekLength: TimeInterval = 7 * 24 * 3600

    private static let firstNames = [
        "Ava", "Mateo", "Priya", "Kofi", "Yuki", "Lena", "Diego", "Noor", "Finn", "Zara",
        "Hugo", "Amara", "Ravi", "Elsie", "Tomas", "Ingrid", "Kai", "Mira", "Oscar", "Nadia",
        "Bruno", "Sana", "Theo", "Leila", "Emeka", "Rosa", "Jonas", "Ines", "Arlo", "Freya",
        "Marek", "Chidi", "Suri", "Otto", "Vera",
    ]
    private static let surnames = [
        "Diner", "Grill", "Kitchen", "Bistro", "Cantina", "Deli", "Tavern", "Counter",
        "Wok", "Bakery", "Smokehouse", "Creamery",
    ]

    static func name(seed: Int) -> String {
        let rng = SeededRandom(seed: seed)
        return "\(firstNames[rng.next(firstNames.count)])'s \(surnames[rng.next(surnames.count)])"
    }

    /// Seeds a fresh week. Rival rates are pinned to the player's own income so the table is
    /// always competitive rather than trivially won or hopeless.
    static func newWeek(tier: LeagueTier, playerRate: Double, now: Date, seasonsPlayed: Int) -> LeagueState {
        let baseline = max(playerRate, 1)
        var rivals: [LeagueRival] = []
        for index in 0..<(size - 1) {
            let rng = SeededRandom(seed: index &* 7919 &+ Int(now.timeIntervalSince1970) &+ seasonsPlayed)
            let jitter = 0.35 + Double(rng.next(150)) / 100.0     // 0.35 ... 1.85
            rivals.append(LeagueRival(
                id: index,
                name: name(seed: index &* 31 &+ seasonsPlayed &* 17),
                rate: baseline * jitter * tier.rivalStrength,
                score: 0
            ))
        }
        return LeagueState(tier: tier, score: 0, rivals: rivals, startedAt: now,
                           endsAt: now.addingTimeInterval(weekLength), lastSettledAt: now,
                           seasonsPlayed: seasonsPlayed)
    }

    /// Advances rival scores for real elapsed time. Called on tick and on foreground, so
    /// rivals keep earning while the app is closed - as they should.
    static func advanceRivals(_ state: inout LeagueState, to now: Date) {
        let elapsed = now.timeIntervalSince(state.lastSettledAt)
        guard elapsed > 0 else { return }
        state.lastSettledAt = now
        let capped = min(elapsed, weekLength)
        for index in state.rivals.indices {
            state.rivals[index].score += state.rivals[index].rate * capped
        }
    }

    static func standings(_ state: LeagueState, playerName: String = "You") -> [LeagueEntry] {
        var rows = state.rivals.map { (id: $0.id, name: $0.name, score: $0.score, isPlayer: false) }
        rows.append((id: -1, name: playerName, score: state.score, isPlayer: true))
        rows.sort { $0.score > $1.score }
        return rows.enumerated().map { index, row in
            LeagueEntry(id: row.id, name: row.name, score: row.score,
                        isPlayer: row.isPlayer, rank: index + 1)
        }
    }

    static func playerRank(_ state: LeagueState) -> Int {
        standings(state).first(where: \.isPlayer)?.rank ?? size
    }

    static func isFinished(_ state: LeagueState, now: Date) -> Bool { now >= state.endsAt }

    /// Works out promotion or relegation and hands back the outcome to show the player.
    static func settle(_ state: LeagueState) -> LeagueOutcome {
        let rank = playerRank(state)
        let tier = state.tier

        if rank <= promoteCount, let next = LeagueTier(rawValue: tier.rawValue + 1) {
            return .promoted(from: tier, to: next, rank: rank, gems: tier.gemReward)
        }
        if rank > size - relegateCount, let previous = LeagueTier(rawValue: tier.rawValue - 1) {
            return .relegated(from: tier, to: previous, rank: rank)
        }
        // Top tier winners and everyone mid-table simply hold their place.
        return .held(tier: tier, rank: rank, gems: rank <= promoteCount ? tier.gemReward : tier.gemReward / 5)
    }

    static func nextTier(after outcome: LeagueOutcome, current: LeagueTier) -> LeagueTier {
        switch outcome {
        case .promoted(_, let to, _, _): return to
        case .relegated(_, let to, _): return to
        case .held: return current
        }
    }

    static func timeRemaining(_ state: LeagueState, now: Date) -> TimeInterval {
        max(0, state.endsAt.timeIntervalSince(now))
    }
}
