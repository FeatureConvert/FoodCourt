import Foundation

/// Kitchen Tools: permanent equipment that DROPS from the game's event moments - Rush
/// completions, VIP catches, Face-Off wins, catering deliveries. Once found, a tool works
/// forever (no equip slots to manage; owning the collection IS the build). Duplicates
/// convert to gems, and the drop table is weighted so the last few finds are genuine
/// chase items - none more than the Gold Spatula, the rarest and best thing in the game.
struct ToolItem: Identifiable, Equatable {
    enum Rarity: Int, Comparable {
        case common = 0, rare, epic, legendary
        static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }
        var label: String {
            switch self {
            case .common: return "COMMON"
            case .rare: return "RARE"
            case .epic: return "EPIC"
            case .legendary: return "LEGENDARY"
            }
        }
    }

    let id: String
    let name: String
    let detail: String
    let symbol: String
    let rarity: Rarity
    /// Drop weight within the table - the Gold Spatula's is deliberately tiny.
    let weight: Double

    // Passive effects, aggregated across everything owned.
    var profitBonus: Double = 0
    var tapBonus: Double = 0
    var goldenChanceBonus: Double = 0
    var ticketBonus: Double = 0
    var offlineEfficiencyBonus: Double = 0
    var comboWindowBonus: Double = 0
}

enum Tools {

    static let all: [ToolItem] = [
        ToolItem(id: "spoon", name: "Wooden Spoon",
                 detail: "+3% profit everywhere", symbol: "fork.knife",
                 rarity: .common, weight: 30, profitBonus: 0.03),
        ToolItem(id: "timer", name: "Egg Timer",
                 detail: "+5% festival tickets", symbol: "timer",
                 rarity: .common, weight: 30, ticketBonus: 0.05),
        ToolItem(id: "pan", name: "Copper Pan",
                 detail: "+5% profit everywhere", symbol: "frying.pan",
                 rarity: .rare, weight: 16, profitBonus: 0.05),
        ToolItem(id: "ladle", name: "Lucky Ladle",
                 detail: "+15% VIP customer odds", symbol: "drop.fill",
                 rarity: .rare, weight: 16, goldenChanceBonus: 0.15),
        ToolItem(id: "knife", name: "Chef's Knife",
                 detail: "+25% tap value", symbol: "scissors",
                 rarity: .epic, weight: 8, tapBonus: 0.25),
        ToolItem(id: "whisk", name: "Silver Whisk",
                 detail: "+8% profit and +5% offline rate", symbol: "tornado",
                 rarity: .epic, weight: 8, profitBonus: 0.08, offlineEfficiencyBonus: 0.05),
        ToolItem(id: "goldspatula", name: "Kristin's Golden Spatula",
                 detail: "+25% profit everywhere and +1s combo window",
                 symbol: "star.square.on.square.fill",
                 rarity: .legendary, weight: 1,
                 profitBonus: 0.25, comboWindowBonus: 1.0),
    ]

    private static let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func tool(_ id: String) -> ToolItem? { index[id] }

    /// Chance any tool drops at all from a given moment - the roll that gates the table.
    enum DropMoment {
        case rushComplete, goldenCollect, expeditionWin, cateringDelivered

        var chance: Double {
            switch self {
            case .rushComplete: return 0.04
            case .goldenCollect: return 0.03
            case .expeditionWin: return 0.20
            case .cateringDelivered: return 0.12
            }
        }
    }

    /// Rolls the weighted table. `roll1` gates the drop, `roll2` picks the item - split so
    /// tests can drive both deterministically. At weight 1 in ~109, the Gold Spatula is
    /// under 1% of drops, which are themselves rare: a real chase, months in the making.
    static func roll(moment: DropMoment, roll1: Double, roll2: Double) -> ToolItem? {
        guard roll1 < moment.chance else { return nil }
        let total = all.reduce(0) { $0 + $1.weight }
        var cursor = roll2 * total
        for tool in all {
            cursor -= tool.weight
            if cursor <= 0 { return tool }
        }
        return all.last
    }

    /// Gems paid when a drop is a duplicate, by rarity.
    static func duplicateGems(_ rarity: ToolItem.Rarity) -> Int {
        switch rarity {
        case .common: return 10
        case .rare: return 25
        case .epic: return 60
        case .legendary: return 300
        }
    }

    // MARK: Aggregated effects

    struct Effects: Equatable {
        var profitMultiplier: Double = 1
        var tapMultiplier: Double = 1
        var goldenChanceMultiplier: Double = 1
        var ticketMultiplier: Double = 1
        var offlineEfficiencyBonus: Double = 0
        var comboWindowBonus: Double = 0
    }

    static func effects(owned: Set<String>) -> Effects {
        var e = Effects()
        for id in owned {
            guard let tool = index[id] else { continue }
            e.profitMultiplier *= 1 + tool.profitBonus
            e.tapMultiplier *= 1 + tool.tapBonus
            e.goldenChanceMultiplier *= 1 + tool.goldenChanceBonus
            e.ticketMultiplier *= 1 + tool.ticketBonus
            e.offlineEfficiencyBonus += tool.offlineEfficiencyBonus
            e.comboWindowBonus += tool.comboWindowBonus
        }
        return e
    }
}
