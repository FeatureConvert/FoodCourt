import Foundation

/// A manager sent away from the roster for a fixed duration, in exchange for a lump sum on
/// return. Assignment lives here rather than on the manager, mirroring how station assignment
/// already lives on the station rather than the manager - one source of truth per relationship.
struct ActiveErrand: Codable, Equatable, Identifiable {
    var id: String
    var managerID: String
    var startedAt: Date
    var duration: TimeInterval
    var rewardGems: Int
    var rewardCoins: Double
    /// `state.prestigeCount` at the moment this errand was dispatched - lets `collectErrand`
    /// tell an honest player's still-pending errand (pay what was promised) apart from the
    /// exploit this field exists to close (send an errand on a huge board, franchise
    /// immediately, then still collect it priced at the board that no longer exists). -1 for
    /// anything decoded from a save written before this field existed, which deliberately
    /// never matches a real prestigeCount (0, 1, 2, ...) - those errands fall back to
    /// collection-time pricing exactly like before, rather than assuming no prestige
    /// happened in a window this save can't actually account for.
    var dispatchedAtPrestigeCount: Int

    enum CodingKeys: String, CodingKey {
        case id, managerID, startedAt, duration, rewardGems, rewardCoins, dispatchedAtPrestigeCount
    }

    init(id: String = UUID().uuidString, managerID: String, startedAt: Date,
         duration: TimeInterval, rewardGems: Int, rewardCoins: Double,
         dispatchedAtPrestigeCount: Int) {
        self.id = id
        self.managerID = managerID
        self.startedAt = startedAt
        self.duration = duration
        self.rewardGems = rewardGems
        self.rewardCoins = rewardCoins
        self.dispatchedAtPrestigeCount = dispatchedAtPrestigeCount
    }

    /// Hand-written for the same reason as every other persisted state in this save: a
    /// synthesized decoder throws on any key an older save doesn't have, which would corrupt
    /// the whole save the moment a new field ships.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        managerID = try c.decodeIfPresent(String.self, forKey: .managerID) ?? ""
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        rewardGems = try c.decodeIfPresent(Int.self, forKey: .rewardGems) ?? 0
        rewardCoins = try c.decodeIfPresent(Double.self, forKey: .rewardCoins) ?? 0
        dispatchedAtPrestigeCount = try c.decodeIfPresent(Int.self, forKey: .dispatchedAtPrestigeCount) ?? -1
    }

    func isComplete(at date: Date) -> Bool { date >= startedAt.addingTimeInterval(duration) }
    func remaining(at date: Date) -> TimeInterval {
        max(0, startedAt.addingTimeInterval(duration).timeIntervalSince(date))
    }
}

struct ErrandOption: Identifiable, Equatable {
    let id: String
    let label: String
    let hours: Double
}

enum Errands {

    static let maxSlots = 2

    static let options: [ErrandOption] = [
        ErrandOption(id: "short", label: "2 hours", hours: 2),
        ErrandOption(id: "medium", label: "6 hours", hours: 6),
        ErrandOption(id: "long", label: "12 hours", hours: 12),
    ]

    /// Cut ~40% in the August review: this was the one gem source the deliberate
    /// faucet-nerf pass (quests -50%, achievements -30%, festival -40%, daily -35%,
    /// league -35%) never touched, and two 12h legendary slots were quietly out-earning
    /// every nerfed source combined at up to 288 gems a day.
    private static func gemsPerHour(_ rarity: ManagerRarity) -> Double {
        switch rarity {
        case .common: return 1
        case .rare: return 2
        case .epic: return 4
        case .legendary: return 7
        }
    }

    /// Coins run at half the manager's normal offline rate - an errand is a genuine tradeoff
    /// against staffing a station, not a strictly better option.
    static func reward(manager: OwnedManager, hours: Double,
                       incomePerSecond: Double) -> (gems: Int, coins: Double) {
        let gems = Int((gemsPerHour(manager.spec.rarity) * hours).rounded())
        let coins = incomePerSecond * hours * 3600 * 0.5
        return (gems, coins)
    }
}
