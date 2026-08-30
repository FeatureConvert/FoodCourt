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
        // id/name/score used to be hard-required here, unlike every sibling element type in
        // the save (ActiveQuest, StationState, ...) - one malformed rival would throw out of
        // this initializer and, since JSONDecoder aborts the whole array on any one element's
        // failure, take LeagueState's `rivals` decode down with it even though THAT field
        // already falls back to `?? []`. decodeIfPresent here closes that gap the same way
        // jitter/isNemesis below already do.
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Rival"
        score = try c.decodeIfPresent(Double.self, forKey: .score) ?? 0
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
    /// Smoothed coins/sec the player is ACTUALLY banking - see `League.advanceRivals`.
    var recentEarnRate: Double = 0
    /// `score` as of the last `advanceRivals` call, so the next call can diff it.
    var scoreAtLastSync: Double = 0

    private enum CodingKeys: String, CodingKey {
        case tier, score, rivals, startedAt, endsAt, lastSettledAt, seasonsPlayed,
             recentEarnRate, scoreAtLastSync
    }

    init(tier: LeagueTier, score: Double, rivals: [LeagueRival], startedAt: Date,
         endsAt: Date, lastSettledAt: Date, seasonsPlayed: Int) {
        self.tier = tier
        self.score = score
        self.rivals = rivals
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.lastSettledAt = lastSettledAt
        self.seasonsPlayed = seasonsPlayed
    }

    init() {}

    // Every save on disk today predates recentEarnRate/scoreAtLastSync - decodeIfPresent
    // so this isn't a decode failure the moment the fix ships (see the migration matrix's
    // whole reason for existing: a wiped veteran save on update day is unforgivable).
    //
    // The other seven fields used to be hard-required (`try c.decode`, no fallback) - the
    // one exception to how every other persisted struct in this save is written. Since
    // GameState decodes League via `decodeIfPresent(...) ?? LeagueState()`, and
    // decodeIfPresent only swallows an ABSENT key (not a present-but-malformed value), a
    // single missing/corrupt field in an otherwise-present "league" blob threw out of here
    // and took the ENTIRE save down with it, not just League progress - the same class of
    // fatal-decode bug this team has already had to fix three times elsewhere (Quests.swift,
    // Balance.swift, GameCenterService.swift), just in decode form instead of Int(Double).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tier = try c.decodeIfPresent(LeagueTier.self, forKey: .tier) ?? .bronze
        score = try c.decodeIfPresent(Double.self, forKey: .score) ?? 0
        // `try?` (not decodeIfPresent) because a malformed *element* inside an otherwise-
        // present array throws a decode error, not a missing-key one - decodeIfPresent alone
        // wouldn't catch that. LeagueRival's own decoder no longer throws for a single bad
        // rival (see above), but this stays as a second line of defense against the key
        // holding a value of the wrong shape entirely.
        rivals = (try? c.decode([LeagueRival].self, forKey: .rivals)) ?? []
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
            ?? Date().addingTimeInterval(League.weekLength)
        lastSettledAt = try c.decodeIfPresent(Date.self, forKey: .lastSettledAt) ?? Date()
        seasonsPlayed = try c.decodeIfPresent(Int.self, forKey: .seasonsPlayed) ?? 0
        recentEarnRate = try c.decodeIfPresent(Double.self, forKey: .recentEarnRate) ?? 0
        scoreAtLastSync = try c.decodeIfPresent(Double.self, forKey: .scoreAtLastSync) ?? score
    }
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
    /// `playerRate` (`automatedRate`) is a floor, not the pace itself - it deliberately
    /// excludes combo, Coffee Break/Rush Hour, and Happy Hour (see its doc comment: those
    /// are real-time and not paid offline). A live report showed a hyperactive player at
    /// 1.14M league score against a 32K second place after three minutes: rivals were
    /// racing the player's steady-state rate while the player's actual score also carried
    /// every one of those multipliers, a gap the combo-cap fix (x5 -> x2) only narrows.
    /// So rivals now race `state.score` itself - exactly what they're being compared
    /// against - smoothed over ~20s so one golden-customer spike doesn't cause a rival
    /// sprint, with `playerRate` as the floor so rivals still crawl forward while the
    /// player is offline (`recentEarnRate` decays toward 0 with no ticks to feed it).
    static func advanceRivals(_ state: inout LeagueState, to now: Date, playerRate: Double) {
        let elapsed = now.timeIntervalSince(state.lastSettledAt)
        guard elapsed > 0 else { return }

        let instantRate = (state.score - state.scoreAtLastSync) / elapsed
        let smoothing = min(1, elapsed / 20)
        state.recentEarnRate += (instantRate - state.recentEarnRate) * smoothing
        state.scoreAtLastSync = state.score

        state.lastSettledAt = now
        let capped = min(elapsed, weekLength)
        let baseline = max(state.recentEarnRate, playerRate, 1)
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
