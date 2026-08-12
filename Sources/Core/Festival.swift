import Foundation

enum FestivalReward: Equatable {
    case gems(Int)
    case coinSeconds(Double)
    case manager(ManagerRarity)
    case boost(multiplier: Double, hours: Double)

    var label: String {
        switch self {
        case .gems(let g): return "\(g) gems"
        case .coinSeconds(let s): return s >= 3600 ? "\(Format.trim(s / 3600))h income" : "\(Int(s / 60))m income"
        case .manager(let r): return "\(r.label) staff"
        case .boost(let m, let h): return "×\(Format.trim(m)) for \(Format.trim(h))h"
        }
    }

    var symbol: String {
        switch self {
        case .gems: return "diamond.fill"
        case .coinSeconds: return "dollarsign.circle.fill"
        case .manager: return "person.crop.circle.badge.checkmark"
        case .boost: return "bolt.fill"
        }
    }
}

struct FestivalTier: Identifiable, Equatable {
    let index: Int              // 1-based
    let ticketsRequired: Int    // cumulative
    let free: FestivalReward
    let premium: FestivalReward
    var id: Int { index }
}

struct FestivalState: Codable, Equatable {
    var seasonID: Int = 1
    var tickets: Int = 0
    var claimedFree: [Int] = []
    var claimedPremium: [Int] = []
    var premiumUnlocked: Bool = false
    var endsAt: Date = Date().addingTimeInterval(Festival.seasonLength)
    /// Carries over between seasons so the fractional drip isn't lost on rollover.
    var serveCounter: Int = 0
    /// Tickets this season that came from serving, so the drip can be capped.
    var ticketsFromServing: Int = 0

    enum CodingKeys: String, CodingKey {
        case seasonID, tickets, claimedFree, claimedPremium, premiumUnlocked, endsAt,
             serveCounter, ticketsFromServing
    }

    init(seasonID: Int = 1, tickets: Int = 0, claimedFree: [Int] = [], claimedPremium: [Int] = [],
         premiumUnlocked: Bool = false, endsAt: Date = Date().addingTimeInterval(Festival.seasonLength),
         serveCounter: Int = 0, ticketsFromServing: Int = 0) {
        self.seasonID = seasonID
        self.tickets = tickets
        self.claimedFree = claimedFree
        self.claimedPremium = claimedPremium
        self.premiumUnlocked = premiumUnlocked
        self.endsAt = endsAt
        self.serveCounter = serveCounter
        self.ticketsFromServing = ticketsFromServing
    }

    /// Hand-written for the same reason as every other persisted state in this save: a
    /// synthesized decoder throws on any key an older save doesn't have, which would corrupt
    /// the whole save the moment a new field ships.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seasonID = try c.decodeIfPresent(Int.self, forKey: .seasonID) ?? 1
        tickets = try c.decodeIfPresent(Int.self, forKey: .tickets) ?? 0
        claimedFree = try c.decodeIfPresent([Int].self, forKey: .claimedFree) ?? []
        claimedPremium = try c.decodeIfPresent([Int].self, forKey: .claimedPremium) ?? []
        premiumUnlocked = try c.decodeIfPresent(Bool.self, forKey: .premiumUnlocked) ?? false
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
            ?? Date().addingTimeInterval(Festival.seasonLength)
        serveCounter = try c.decodeIfPresent(Int.self, forKey: .serveCounter) ?? 0
        ticketsFromServing = try c.decodeIfPresent(Int.self, forKey: .ticketsFromServing) ?? 0
    }
}

enum Festival {

    static let tierCount = 30
    /// A week, matching the league. Three days was too short to sell a pass for.
    static let seasonLength: TimeInterval = 7 * 24 * 3600
    static let premiumProductID = "com.fable.foodcourt.pack.festival"

    // Ticket sources.
    static let servesPerTicket = 25
    static let ticketsPerQuest = 40
    static let ticketsPerDaily = 100
    static let ticketsPerRush = 60

    /// The serve drip scales with income, and income scales without limit - left uncapped an
    /// established player earned the entire track hundreds of times over in a single season,
    /// which defeats the point of a season. Serving can carry the player this far and no
    /// further; the rest has to come from turning up for dailies, goals, and rushes.
    /// Tuned so a player who turns up daily and clears goals finishes the track with a
    /// little room, while serving alone leaves them well short.
    static let serveShareOfTrack = 0.45
    static var maxTicketsFromServing: Int {
        Int(Double(ticketsRequired(forTier: tierCount)) * serveShareOfTrack)
    }

    static let seasonName = "Street Food Carnival"

    // MARK: Season modifiers

    /// One gameplay twist per season, rotating with the season id - across the six-month
    /// arc the carnival plays differently every week instead of re-running the same track
    /// twenty-six times. Effects hook the same paths everything else uses.
    struct SeasonModifier: Equatable {
        let id: String
        let title: String
        let detail: String
        var tapsPerTicket: Int? = nil          // taps also drip tickets
        var offlineEfficiencyBonus: Double = 0
        var goldenChanceMultiplier: Double = 1
        var tierCoinMultiplier: Double = 1     // coin rewards on the track pay more
    }

    static let seasonModifiers: [SeasonModifier] = [
        SeasonModifier(id: "tapfrenzy", title: "Tap Frenzy",
                       detail: "Every 40 taps earns a festival ticket this season.",
                       tapsPerTicket: 40),
        SeasonModifier(id: "overtime", title: "Overtime",
                       detail: "+25% offline earnings all season.",
                       offlineEfficiencyBonus: 0.25),
        SeasonModifier(id: "goldenweek", title: "Golden Week",
                       detail: "VIP customers appear twice as often this season.",
                       goldenChanceMultiplier: 2),
        SeasonModifier(id: "bigspender", title: "Big Spender",
                       detail: "Coin rewards on the track pay double this season.",
                       tierCoinMultiplier: 2),
    ]

    static func modifier(seasonID: Int) -> SeasonModifier {
        seasonModifiers[((seasonID % seasonModifiers.count) + seasonModifiers.count) % seasonModifiers.count]
    }

    static func ticketsRequired(forTier tier: Int) -> Int {
        guard tier > 0 else { return 0 }
        return Int((70 * pow(Double(tier), 1.35)).rounded())
    }

    static func tier(_ index: Int) -> FestivalTier {
        FestivalTier(
            index: index,
            ticketsRequired: ticketsRequired(forTier: index),
            free: freeReward(index),
            premium: premiumReward(index)
        )
    }

    static var allTiers: [FestivalTier] { (1...tierCount).map(tier) }

    private static func freeReward(_ index: Int) -> FestivalReward {
        if index == tierCount { return .manager(.epic) }
        if index % 10 == 0 { return .manager(.rare) }
        if index % 5 == 0 { return .boost(multiplier: 2, hours: 1) }
        // Free-track gems, unlike the premium track, aren't paid for - cut by ~40% so the
        // season's free gem total stops rivaling what quests alone were handing out.
        if index % 2 == 0 { return .gems(6 + index * 6 / 10) }
        return .coinSeconds(Double(index) * 120)
    }

    private static func premiumReward(_ index: Int) -> FestivalReward {
        if index == tierCount { return .manager(.legendary) }
        if index % 10 == 0 { return .manager(.epic) }
        if index % 5 == 0 { return .manager(.rare) }
        if index % 2 == 0 { return .coinSeconds(Double(index) * 600) }
        return .gems(25 + index * 2)
    }

    /// Highest tier the current ticket count has reached.
    static func unlockedTier(tickets: Int) -> Int {
        var reached = 0
        for index in 1...tierCount where tickets >= ticketsRequired(forTier: index) {
            reached = index
        }
        return reached
    }

    static func progressToNextTier(tickets: Int) -> (current: Int, next: Int, fraction: Double) {
        let current = unlockedTier(tickets: tickets)
        guard current < tierCount else { return (current, current, 1) }
        let floorTickets = ticketsRequired(forTier: current)
        let ceilTickets = ticketsRequired(forTier: current + 1)
        let span = max(1, ceilTickets - floorTickets)
        return (current, current + 1, min(1, Double(tickets - floorTickets) / Double(span)))
    }

    /// `premiumActive` covers both a bought pass and VIP, which includes it every season.
    static func canClaim(_ state: FestivalState, tier: Int, premium: Bool,
                         premiumActive: Bool) -> Bool {
        guard tier <= unlockedTier(tickets: state.tickets) else { return false }
        if premium && !premiumActive { return false }
        return !(premium ? state.claimedPremium : state.claimedFree).contains(tier)
    }

    static func unclaimedCount(_ state: FestivalState, premiumActive: Bool) -> Int {
        let reached = unlockedTier(tickets: state.tickets)
        guard reached > 0 else { return 0 }
        var count = 0
        for tier in 1...reached {
            if canClaim(state, tier: tier, premium: false, premiumActive: premiumActive) { count += 1 }
            if canClaim(state, tier: tier, premium: true, premiumActive: premiumActive) { count += 1 }
        }
        return count
    }

    /// Rolls the season over once it lapses. Premium ownership is per-season, matching how
    /// real passes work, so it resets too. A multi-week absence deliberately settles as a
    /// single fresh season rather than replaying every missed one - there is nothing to
    /// back-pay on tracks nobody played, and `endsAt = now + seasonLength` gives the
    /// returning player a full week rather than a season already half over.
    @discardableResult
    static func rolloverIfNeeded(_ state: inout FestivalState, now: Date) -> Bool {
        guard now >= state.endsAt else { return false }
        state.seasonID += 1
        state.tickets = 0
        state.claimedFree = []
        state.claimedPremium = []
        state.premiumUnlocked = false
        state.serveCounter = 0
        state.ticketsFromServing = 0
        state.endsAt = now.addingTimeInterval(seasonLength)
        return true
    }

    static func timeRemaining(_ state: FestivalState, now: Date) -> TimeInterval {
        max(0, state.endsAt.timeIntervalSince(now))
    }
}
