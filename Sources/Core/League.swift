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
    // Cut ~35% in the same pass as quests/achievements/festival/daily - a weekly cadence
    // doesn't make a source exempt from the same "free gems add up too fast" problem.
    var gemReward: Int {
        switch self {
        case .bronze: return 16
        case .silver: return 32
        case .gold: return 65
        case .diamond: return 115
        }
    }
}

struct LeagueRival: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    /// Ratio applied to the player's *current* rate each tick (see `League.advanceRivals`) -
    /// fixed for the week so each rival has a consistent relative pace, but never a frozen
    /// absolute number, so a rival can't fall arbitrarily far behind as the player grows.
    var jitter: Double
    var score: Double
    /// The one rival who follows the player from season to season - same name every week,
    /// pace pinned just above the player's. "Beat Rossi's Bistro this week" is a hook;
    /// twenty-nine anonymous rows are not.
    var isNemesis: Bool = false

    private enum CodingKeys: String, CodingKey { case id, name, jitter, score, isNemesis }

    init(id: Int, name: String, jitter: Double, score: Double, isNemesis: Bool = false) {
        self.id = id
        self.name = name
        self.jitter = jitter
        self.score = score
        self.isNemesis = isNemesis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        score = try c.decode(Double.self, forKey: .score)
        // Saves from before rivals tracked the player's pace stored an absolute `rate`
        // instead - there's nothing to convert, so reroll a stable jitter for this rival
        // rather than losing the whole league (and the rest of the save) to a decode failure.
        if let jitter = try c.decodeIfPresent(Double.self, forKey: .jitter) {
            self.jitter = jitter
        } else {
            let rng = SeededRandom(seed: id &* 7919)
            self.jitter = 0.35 + Double(rng.next(150)) / 100.0
        }
        isNemesis = try c.decodeIfPresent(Bool.self, forKey: .isNemesis) ?? false
    }
}

struct LeagueEntry: Identifiable, Equatable {
    let id: Int
    let name: String
    let score: Double
    let isPlayer: Bool
    let rank: Int
    var isNemesis: Bool = false
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

    /// Seeds a fresh week. Each rival gets a fixed jitter ratio around the player's pace -
    /// the *effective* rate is recomputed every `advanceRivals` call against the player's
    /// current income, so the table stays competitive all week instead of only at the start.
    static func newWeek(tier: LeagueTier, now: Date, seasonsPlayed: Int,
                        nemesisSeed: Int? = nil) -> LeagueState {
        var rivals: [LeagueRival] = []
        for index in 0..<(size - 1) {
            let rng = SeededRandom(seed: index &* 7919 &+ Int(now.timeIntervalSince1970) &+ seasonsPlayed)
            let jitter = 0.35 + Double(rng.next(150)) / 100.0     // 0.35 ... 1.85
            rivals.append(LeagueRival(
                id: index,
                name: name(seed: index &* 31 &+ seasonsPlayed &* 17),
                jitter: jitter,
                score: 0
            ))
        }
        // Rival 0 becomes the persistent nemesis: name derived from the save's stable
        // seed (so it never changes), pace pinned to 1.02-1.14x the player's - always
        // beatable, never ignorable.
        if let seed = nemesisSeed, !rivals.isEmpty {
            let rng = SeededRandom(seed: seed)
            rivals[0] = LeagueRival(id: 0, name: name(seed: seed),
                                    jitter: 1.02 + Double(rng.next(13)) / 100.0,
                                    score: 0, isNemesis: true)
        }
        return LeagueState(tier: tier, score: 0, rivals: rivals, startedAt: now,
                           endsAt: now.addingTimeInterval(weekLength), lastSettledAt: now,
                           seasonsPlayed: seasonsPlayed)
    }

    /// Advances rival scores for real elapsed time. Called on tick and on foreground, so
    /// rivals keep earning while the app is closed - as they should.
    ///
    /// `playerRate` is the player's *current* income, not a value pinned when the week
    /// started - an idle economy can grow the player's rate by orders of magnitude over a
    /// single week, and a rival still earning at week-1 pace on week-7 isn't a rival anymore.
    static func advanceRivals(_ state: inout LeagueState, to now: Date, playerRate: Double) {
        let elapsed = now.timeIntervalSince(state.lastSettledAt)
        guard elapsed > 0 else { return }
        state.lastSettledAt = now
        let capped = min(elapsed, weekLength)
        let baseline = max(playerRate, 1)
        for index in state.rivals.indices {
            let rate = baseline * state.rivals[index].jitter * state.tier.rivalStrength
            state.rivals[index].score += rate * capped
        }
    }

    static func standings(_ state: LeagueState, playerName: String = "You") -> [LeagueEntry] {
        var rows = state.rivals.map {
            (id: $0.id, name: $0.name, score: $0.score, isPlayer: false, isNemesis: $0.isNemesis)
        }
        rows.append((id: -1, name: playerName, score: state.score, isPlayer: true, isNemesis: false))
        rows.sort { $0.score > $1.score }
        return rows.enumerated().map { index, row in
            LeagueEntry(id: row.id, name: row.name, score: row.score,
                        isPlayer: row.isPlayer, rank: index + 1, isNemesis: row.isNemesis)
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
