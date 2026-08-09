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
    /// True for anything bought with gems, real money, or handed out as a reward (festival,
    /// league, IAP) - false for a coin-hired or tutorial-free trainee. `GameEngine.prestige()`
    /// wipes the roster back down to just this set, so staffing a reset board again costs
    /// real coins and real time instead of being a free instant reassignment - that free
    /// reassignment was most of why repeat prestige cycles had gotten absurdly fast.
    var premium: Bool
    /// Only set for Trainee hires - every other spec already has its own character name
    /// (Rush Rosa, Chef August, ...), but Trainee is the single generic coin-hire used for
    /// every ordinary staffing, so a player with a full venue saw a wall of identically
    /// named "Trainee" cards with no way to tell them apart. Picked once at hire time.
    var displayName: String?
    /// Total days spent assigned to a station (see `GameEngine.accrueBondTime`). Long
    /// service pays: +2% station profit per bond level, and a roster that's been together
    /// for months is one more reason not to drift away.
    var bondDays: Double = 0

    var spec: ManagerSpec { ManagerCatalog.spec(specID) }
    var name: String { displayName ?? spec.name }

    /// 0-5, crossing at 1/3/7/14/30 days of assigned service.
    var bondLevel: Int { Self.bondThresholds.filter { bondDays >= $0 }.count }
    static let bondThresholds: [Double] = [1, 3, 7, 14, 30]
    var bondProfitMultiplier: Double { 1 + 0.02 * Double(bondLevel) }

    static func make(_ specID: String, premium: Bool = false) -> OwnedManager {
        let displayName = specID == ManagerCatalog.traineeID ? ManagerCatalog.randomTraineeName() : nil
        return OwnedManager(id: UUID().uuidString, specID: specID, premium: premium, displayName: displayName)
    }

    private enum CodingKeys: String, CodingKey { case id, specID, premium, displayName, bondDays }

    init(id: String, specID: String, premium: Bool, displayName: String? = nil) {
        self.id = id
        self.specID = specID
        self.premium = premium
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        specID = try c.decode(String.self, forKey: .specID)
        // Saves from before this field existed have no record of how a manager was acquired.
        // Defaulting to false (coin-tier) is the conservative read: it means those managers
        // are swept on the player's very next prestige, same as this fix intends for anyone
        // hired from here on - there's no way to retroactively know which of them were
        // actually gem- or IAP-bought, so this can't be perfectly fair, only consistent.
        premium = try c.decodeIfPresent(Bool.self, forKey: .premium) ?? false
        bondDays = try c.decodeIfPresent(Double.self, forKey: .bondDays) ?? 0
        // Pre-existing trainees never got a name; give them one now rather than leaving them
        // stuck as one more anonymous "Trainee" forever.
        if let existing = try c.decodeIfPresent(String.self, forKey: .displayName) {
            displayName = existing
        } else {
            displayName = specID == ManagerCatalog.traineeID ? ManagerCatalog.randomTraineeName() : nil
        }
    }
}

enum ManagerCatalog {

    /// The baseline hire. Coins still buy one of these, so the original flow is intact and
    /// old saves migrate onto it cleanly.
    static let traineeID = "trainee"

    static let baseRoster: [ManagerSpec] = [
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

    /// This week's rotating hire - see `GuestChef`. Kept out of `random(rarity:)`'s pool so
    /// they stay exclusive to the weekly purchase rather than leaking into ordinary legendary
    /// grants, but still listed in `all` so an owned guest manager resolves normally.
    static let guestSpecs: [ManagerSpec] = [
        ManagerSpec(id: "guest-remy", name: "Guest Chef Remy", role: "This week only",
                    rarity: .legendary, trait: .venueProfit(1.8), portraitSeed: 210),
        ManagerSpec(id: "guest-mika", name: "Guest Chef Mika", role: "This week only",
                    rarity: .legendary, trait: .stationProfit(2.2), portraitSeed: 224),
        ManagerSpec(id: "guest-theo", name: "Guest Chef Theo", role: "This week only",
                    rarity: .legendary, trait: .stationSpeed(2.0), portraitSeed: 238),
        ManagerSpec(id: "guest-ines", name: "Guest Chef Inès", role: "This week only",
                    rarity: .legendary, trait: .tapValue(2.5), portraitSeed: 252),
    ]

    static let all: [ManagerSpec] = baseRoster + guestSpecs

    private static let index: [String: ManagerSpec] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func spec(_ id: String) -> ManagerSpec {
        index[id] ?? all[0]
    }

    static func specs(rarity: ManagerRarity) -> [ManagerSpec] {
        baseRoster.filter { $0.rarity == rarity }
    }

    /// Used by quest, festival, and league rewards to hand out staff of a given quality.
    static func random(rarity: ManagerRarity, seed: Int) -> ManagerSpec {
        let pool = specs(rarity: rarity)
        guard !pool.isEmpty else { return baseRoster[0] }
        // Double-modulo rather than abs(): abs(Int.min) is a trap, and callers' seeds are
        // an implementation detail this shouldn't have to trust.
        return pool[((seed % pool.count) + pool.count) % pool.count]
    }

    /// First names for Trainee hires - deliberately disjoint from every named character above
    /// (Sam, Tina, Otto, Rosa, Milo, Wren, Kip, Vera, Dex, Pia, Cleo, August, Nova, and the
    /// guest chefs) so a full roster never reads as two different people sharing a name.
    private static let traineeNames = [
        "Jordan", "Alexis", "Casey", "Priya", "Malik", "Elena", "Diego", "Noor",
        "Finn", "Zara", "Hugo", "Amara", "Ravi", "Sofia", "Tomas", "Ingrid",
        "Kai", "Mira", "Oscar", "Nadia", "Bruno", "Sana", "Petra", "Leila",
    ]

    static func randomTraineeName(seed: Int = Int.random(in: 0..<1_000_000)) -> String {
        traineeNames[((seed % traineeNames.count) + traineeNames.count) % traineeNames.count]
    }
}

// MARK: - Synergies

/// Named crews: staff BOTH members anywhere in the same venue and the whole venue gets the
/// bonus. Turns staffing from slot-filling into a small puzzle, and gives the bench roster
/// a reason to exist beyond errands - the pair you're missing is suddenly worth hunting.
struct ManagerSynergy: Identifiable, Equatable {
    let id: String
    let title: String
    let memberIDs: [String]
    let detail: String
    /// Venue-wide profit multiplier while the crew is together.
    let venueProfit: Double
}

enum Synergies {

    static let all: [ManagerSynergy] = [
        ManagerSynergy(id: "clockwork", title: "Clockwork Crew",
                       memberIDs: ["sam", "otto"],
                       detail: "Speedy Sam + Orderly Otto: +10% venue profit", venueProfit: 1.10),
        ManagerSynergy(id: "frontline", title: "Front Line",
                       memberIDs: ["tina", "kip"],
                       detail: "Tips Tina + Quick-Hands Kip: +10% venue profit", venueProfit: 1.10),
        ManagerSynergy(id: "closers", title: "The Closers",
                       memberIDs: ["milo", "vera"],
                       detail: "Margin Milo + Front-of-House Vera: +15% venue profit", venueProfit: 1.15),
        ManagerSynergy(id: "nightcrew", title: "Night Crew",
                       memberIDs: ["wren", "nova"],
                       detail: "Night-Shift Wren + Nova the Nightowl: +15% venue profit", venueProfit: 1.15),
        ManagerSynergy(id: "showstoppers", title: "Showstoppers",
                       memberIDs: ["cleo", "dex", "august"],
                       detail: "Cleo + Dex + Chef August: +25% venue profit", venueProfit: 1.25),
    ]

    /// Crews fully staffed in the given venue.
    static func active(in venueSpecIDs: Set<String>) -> [ManagerSynergy] {
        all.filter { synergy in synergy.memberIDs.allSatisfy(venueSpecIDs.contains) }
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
