import Foundation

enum ResearchEffect: Equatable {
    case globalProfit(Double)     // added multiplier per rank
    case offlineCapHours(Double)  // added hours per rank
    case tapValue(Double)
    case comboCap(Double)         // extra combo steps
    case managerSpeed(Double)
    case ticketRate(Double)
    case goldenChance(Double)
    case rushSeconds(Double)
    case offlineEfficiency(Double)
}

struct ResearchNode: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let branch: ResearchBranch
    let maxRank: Int
    let baseCost: Int
    let requires: [String]
    let effect: ResearchEffect

    /// Hybrid pricing: the static 2.4-growth curve is only a FLOOR; past the first few
    /// franchises, `Balance.researchAwardCostFraction` of the player's latest Franchise
    /// award dominates.
    ///
    /// History, because this took four passes to get right: static growth went
    /// 1.6 -> 1.75 -> 1.95 -> 2.4, each retune extrapolating "how fast stars arrive" from
    /// a one-week measurement. The August review finally simulated the full arc and found
    /// star income COMPOUNDS (stars -> multiplier -> earnings -> stars): the "~6 month"
    /// 2.4 tree actually fell in under two weeks in every simulated profile, because each
    /// board multiplies lifetime earnings by orders of magnitude. No fixed number can pace
    /// a currency like that - hence award-proportional pricing, which self-scales with any
    /// play intensity and lands full completion at ~6 months of a 5-day prestige cadence
    /// (see the fraction's doc in Balance.swift for the simulated numbers).
    ///
    /// Rank 0 on the cheapest nodes still costs 30-40 stars for a brand-new player (the
    /// static floor governs until awards grow), so the first taste of the system stays
    /// affordable off a first-ever Franchise.
    func cost(forRank rank: Int, award: Int = 0) -> Int {
        let floorCost = Int((Double(baseCost) * pow(2.4, Double(rank))).rounded())
        let scaled = Int(Balance.researchAwardCostFraction * Double(award))
        return max(floorCost, scaled)
    }
}

enum ResearchBranch: String, CaseIterable, Identifiable {
    case kitchen, service, empire, nightshift
    var id: String { rawValue }

    var title: String {
        switch self {
        case .kitchen: return "Kitchen"
        case .service: return "Service"
        case .empire: return "Empire"
        case .nightshift: return "Night Shift"
        }
    }
    var blurb: String {
        switch self {
        case .kitchen: return "Cook faster, earn more"
        case .service: return "Reward hands-on play"
        case .empire: return "Scale the whole operation"
        case .nightshift: return "Earn while you're away"
        }
    }
}

enum Research {

    static let nodes: [ResearchNode] = [
        // Kitchen
        ResearchNode(id: "prep", title: "Prep Stations", detail: "+4% profit everywhere",
                     symbol: "fork.knife", branch: .kitchen, maxRank: 10, baseCost: 30,
                     requires: [], effect: .globalProfit(0.04)),
        ResearchNode(id: "burners", title: "Extra Burners", detail: "+6% manager speed",
                     symbol: "flame.fill", branch: .kitchen, maxRank: 8, baseCost: 50,
                     requires: ["prep"], effect: .managerSpeed(0.06)),
        ResearchNode(id: "rushline", title: "Rush Training", detail: "+5s of Rush Hour",
                     symbol: "timer", branch: .kitchen, maxRank: 6, baseCost: 80,
                     requires: ["burners"], effect: .rushSeconds(5)),

        // Service
        ResearchNode(id: "tills", title: "Faster Tills", detail: "+15% tap value",
                     symbol: "hand.tap.fill", branch: .service, maxRank: 10, baseCost: 30,
                     requires: [], effect: .tapValue(0.15)),
        ResearchNode(id: "rhythm", title: "Kitchen Rhythm", detail: "+2 combo steps",
                     symbol: "waveform.path", branch: .service, maxRank: 8, baseCost: 60,
                     requires: ["tills"], effect: .comboCap(2)),
        ResearchNode(id: "regulars", title: "Loyal Regulars", detail: "+20% golden customer odds",
                     symbol: "sparkles", branch: .service, maxRank: 6, baseCost: 90,
                     requires: ["rhythm"], effect: .goldenChance(0.2)),

        // Empire
        ResearchNode(id: "brand", title: "Brand Recognition", detail: "+6% profit everywhere",
                     symbol: "building.2.fill", branch: .empire, maxRank: 10, baseCost: 60,
                     requires: [], effect: .globalProfit(0.06)),
        ResearchNode(id: "logistics", title: "Logistics", detail: "+25% festival tickets",
                     symbol: "shippingbox.fill", branch: .empire, maxRank: 6, baseCost: 80,
                     requires: ["brand"], effect: .ticketRate(0.25)),
        ResearchNode(id: "franchise", title: "Franchise Playbook", detail: "+10% profit everywhere",
                     symbol: "crown.fill", branch: .empire, maxRank: 5, baseCost: 150,
                     requires: ["logistics"], effect: .globalProfit(0.1)),

        // Night shift
        ResearchNode(id: "keys", title: "Spare Keys", detail: "+2h offline cap",
                     symbol: "key.fill", branch: .nightshift, maxRank: 8, baseCost: 40,
                     requires: [], effect: .offlineCapHours(2)),
        ResearchNode(id: "handover", title: "Clean Handover", detail: "+6% offline rate",
                     symbol: "moon.stars.fill", branch: .nightshift, maxRank: 8, baseCost: 60,
                     requires: ["keys"], effect: .offlineEfficiency(0.06)),
        ResearchNode(id: "lockin", title: "Lock-In Contracts", detail: "+5% profit everywhere",
                     symbol: "lock.shield.fill", branch: .nightshift, maxRank: 5, baseCost: 120,
                     requires: ["handover"], effect: .globalProfit(0.05)),
    ]

    private static let index: [String: ResearchNode] =
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

    static func node(_ id: String) -> ResearchNode? { index[id] }

    static func nodes(in branch: ResearchBranch) -> [ResearchNode] {
        nodes.filter { $0.branch == branch }
    }

    /// A node opens once every prerequisite has at least one rank.
    static func isUnlocked(_ node: ResearchNode, ranks: [String: Int]) -> Bool {
        node.requires.allSatisfy { (ranks[$0] ?? 0) > 0 }
    }

    static func canBuy(_ node: ResearchNode, ranks: [String: Int], stars: Int,
                       award: Int = 0) -> Bool {
        let rank = ranks[node.id] ?? 0
        return rank < node.maxRank
            && isUnlocked(node, ranks: ranks)
            && stars >= node.cost(forRank: rank, award: award)
    }

    // MARK: Aggregated effects

    static func effects(ranks: [String: Int]) -> ResearchEffects {
        var result = ResearchEffects()
        for (id, rank) in ranks {
            guard rank > 0, let node = index[id] else { continue }
            let n = Double(min(rank, node.maxRank))
            switch node.effect {
            case .globalProfit(let v):      result.globalProfit += v * n
            case .offlineCapHours(let v):   result.offlineCapHours += v * n
            case .tapValue(let v):          result.tapValue += v * n
            case .comboCap(let v):          result.comboCap += v * n
            case .managerSpeed(let v):      result.managerSpeed += v * n
            case .ticketRate(let v):        result.ticketRate += v * n
            case .goldenChance(let v):      result.goldenChance += v * n
            case .rushSeconds(let v):       result.rushSeconds += v * n
            case .offlineEfficiency(let v): result.offlineEfficiency += v * n
            }
        }
        return result
    }
}

/// Additive bonuses resolved once, then read by the engine on every tick.
struct ResearchEffects: Equatable {
    var globalProfit: Double = 0
    var offlineCapHours: Double = 0
    var tapValue: Double = 0
    var comboCap: Double = 0
    var managerSpeed: Double = 0
    var ticketRate: Double = 0
    var goldenChance: Double = 0
    var rushSeconds: Double = 0
    var offlineEfficiency: Double = 0

    var profitMultiplier: Double { 1 + globalProfit }
    var tapMultiplier: Double { 1 + tapValue }
    var managerSpeedMultiplier: Double { 1 + managerSpeed }
    var ticketMultiplier: Double { 1 + ticketRate }
}
