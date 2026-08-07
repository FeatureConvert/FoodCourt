import Foundation

enum ManagerRarity: String, Codable, CaseIterable, Comparable {
    case common, rare, epic, legendary

    var order: Int {
        switch self {
        case .common: return 0
        case .rare: return 1
        case .epic: return 2
        case .legendary: return 3
        }
    }
    var label: String { rawValue.uppercased() }
    static func < (a: ManagerRarity, b: ManagerRarity) -> Bool { a.order < b.order }
}

/// What a hired character actually does. Traits are what turn "hasManager: true" into a
/// roster the player has opinions about.
enum ManagerTrait: Equatable {
    case stationSpeed(Double)   // multiplier on the assigned station's cycle rate
    case stationProfit(Double)  // multiplier on the assigned station's payout
    case venueProfit(Double)    // multiplier across the whole venue
    case tapValue(Double)       // multiplier on manual taps
    case offlineBonus(Double)   // multiplier on offline earnings
    case comboRetention(Double) // extra seconds on the combo window

    var detail: String {
        switch self {
        case .stationSpeed(let v):   return "+\(pct(v - 1)) station speed"
        case .stationProfit(let v):  return "+\(pct(v - 1)) station profit"
        case .venueProfit(let v):    return "+\(pct(v - 1)) venue profit"
        case .tapValue(let v):       return "+\(pct(v - 1)) tap value"
        case .offlineBonus(let v):   return "+\(pct(v - 1)) offline earnings"
        case .comboRetention(let v): return "+\(String(format: "%.1f", v))s combo window"
        }
    }

    private func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

struct ManagerSpec: Identifiable, Equatable {
    let id: String
    let name: String
    let role: String
    let rarity: ManagerRarity
    let trait: ManagerTrait
    /// Feeds `CustomerSprite`, so every manager already has a portrait for free.
    let portraitSeed: Int
}

/// A manager the player owns. Assignment lives on the station rather than here so there is
/// exactly one source of truth for "who is running this counter".
struct OwnedManager: Codable, Equatable, Identifiable {
    var id: String            // unique instance id
    var specID: String

    var spec: ManagerSpec { ManagerCatalog.spec(specID) }

    static func make(_ specID: String) -> OwnedManager {
        OwnedManager(id: UUID().uuidString, specID: specID)
    }
}

enum ManagerCatalog {

    /// The baseline hire. Coins still buy one of these, so the original flow is intact and
    /// old saves migrate onto it cleanly.
    static let traineeID = "trainee"

    static let all: [ManagerSpec] = [
        ManagerSpec(id: traineeID, name: "Trainee", role: "Eager and cheap",
                    rarity: .common, trait: .stationSpeed(1.0), portraitSeed: 11),
        ManagerSpec(id: "sam", name: "Speedy Sam", role: "Never stops moving",
                    rarity: .common, trait: .stationSpeed(1.15), portraitSeed: 23),
        ManagerSpec(id: "tina", name: "Tips Tina", role: "Everyone's favourite",
                    rarity: .common, trait: .stationProfit(1.2), portraitSeed: 37),
        ManagerSpec(id: "otto", name: "Orderly Otto", role: "Runs a tight pass",
                    rarity: .common, trait: .stationSpeed(1.2), portraitSeed: 52),

        ManagerSpec(id: "rosa", name: "Rush Rosa", role: "Thrives in chaos",
                    rarity: .rare, trait: .stationSpeed(1.35), portraitSeed: 64),
        ManagerSpec(id: "milo", name: "Margin Milo", role: "Counts every cent",
                    rarity: .rare, trait: .stationProfit(1.45), portraitSeed: 78),
        ManagerSpec(id: "wren", name: "Night-Shift Wren", role: "Works while you sleep",
                    rarity: .rare, trait: .offlineBonus(1.3), portraitSeed: 91),
        ManagerSpec(id: "kip", name: "Quick-Hands Kip", role: "Faster than the till",
                    rarity: .rare, trait: .tapValue(1.5), portraitSeed: 103),

        ManagerSpec(id: "vera", name: "Front-of-House Vera", role: "Lifts the whole room",
                    rarity: .epic, trait: .venueProfit(1.25), portraitSeed: 117),
        ManagerSpec(id: "dex", name: "Double-Time Dex", role: "Two hands, four pans",
                    rarity: .epic, trait: .stationSpeed(1.7), portraitSeed: 128),
        ManagerSpec(id: "pia", name: "Prep-Ahead Pia", role: "Always three steps early",
                    rarity: .epic, trait: .stationProfit(1.8), portraitSeed: 141),
        ManagerSpec(id: "cleo", name: "Crowd-Reader Cleo", role: "Keeps the rhythm going",
                    rarity: .epic, trait: .comboRetention(0.6), portraitSeed: 155),

        ManagerSpec(id: "august", name: "Chef August", role: "Michelin, allegedly",
                    rarity: .legendary, trait: .venueProfit(1.6), portraitSeed: 168),
        ManagerSpec(id: "nova", name: "Nova the Nightowl", role: "The empire never sleeps",
                    rarity: .legendary, trait: .offlineBonus(2.0), portraitSeed: 182),
    ]

    private static let index: [String: ManagerSpec] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func spec(_ id: String) -> ManagerSpec {
        index[id] ?? all[0]
    }

    static func specs(rarity: ManagerRarity) -> [ManagerSpec] {
        all.filter { $0.rarity == rarity }
    }

    /// Used by quest, festival, and league rewards to hand out staff of a given quality.
    static func random(rarity: ManagerRarity, seed: Int) -> ManagerSpec {
        let pool = specs(rarity: rarity)
        guard !pool.isEmpty else { return all[0] }
        return pool[abs(seed) % pool.count]
    }
}

// MARK: - Trait aggregation

/// Resolved manager effects for one station, so the engine never walks the roster mid-tick.
struct ManagerEffects: Equatable {
    var stationSpeed: Double = 1
    var stationProfit: Double = 1
    var venueProfit: Double = 1
    var tapValue: Double = 1
    var offlineBonus: Double = 1
    var comboRetention: Double = 0

    mutating func apply(_ trait: ManagerTrait) {
        switch trait {
        case .stationSpeed(let v):   stationSpeed *= v
        case .stationProfit(let v):  stationProfit *= v
        case .venueProfit(let v):    venueProfit *= v
        case .tapValue(let v):       tapValue *= v
        case .offlineBonus(let v):   offlineBonus *= v
        case .comboRetention(let v): comboRetention += v
        }
    }
}
