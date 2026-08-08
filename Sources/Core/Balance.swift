import Foundation

// MARK: - Art keys

/// The sprite library draws a dozen composable food forms; every station picks one and
/// recolors it. Twelve well-drawn primitives read better than thirty rushed ones.
enum FoodArt: String, Codable, CaseIterable {
    case fries, bun, cup, stick, cone, plate
    case bowl, nigiri, roll, wedge, wrap, cupcake
}

/// Venue-level look, mapped to a concrete palette in `Theme`.
enum VenueTheme: String, Codable, CaseIterable {
    case burger, sushi, pizza, taco, dessert
}

// MARK: - Specs

struct StationSpec: Identifiable {
    let id: Int
    let name: String
    let art: FoodArt
    /// Hex seeds: primary, secondary, accent. Drives the vector sprite's fill colors.
    let colors: [String]
    let baseCost: Double
    let baseRevenue: Double
    let baseCycle: TimeInterval
    let costGrowth: Double
}

struct VenueSpec: Identifiable {
    let id: Int
    let name: String
    let tagline: String
    let theme: VenueTheme
    let stations: [StationSpec]

    /// What it costs to open this venue's doors, in coins.
    var unlockCost: Double {
        id == 0 ? 0 : stations[0].baseCost * 4_000
    }

    /// Deeper venues pay far more and cost far more - this is what makes moving on feel
    /// like a jump rather than a grind extension.
    var revenueMultiplier: Double { pow(30, Double(id)) }
    var costMultiplier: Double { pow(25, Double(id)) }
}

// MARK: - Milestones

enum MilestoneKind: Equatable {
    case profit(Double)
    case speed(Double)
}

struct Milestone: Equatable {
    let level: Int
    let kind: MilestoneKind

    var label: String {
        switch kind {
        case .profit(let m): return "×\(Format.trim(m)) profit"
        case .speed(let m): return "×\(Format.trim(m)) speed"
        }
    }
}

// MARK: - Balance

/// Every tunable number in the game lives here. Retuning the economy means editing this
/// file and nothing else.
enum Balance {

    // Idle-game convention: each station is roughly an order of magnitude beyond the last,
    // so the "next" station is always the aspirational purchase.
    // Cost growth was tuned too gently against a player who mashes the MAX-buy button: since
    // income per second scales with level, a low growth rate lets levels compound faster than
    // their own cost, and the game degenerates into "buy MAX repeatedly" trivializing every
    // milestone within the first couple of minutes. These values were re-derived by
    // simulating that exact MAX-buy loop against the real cost/revenue formulas rather than
    // guessed - see the balance pass notes for the target curve (first speed milestone ~5min
    // in, second venue ~20min of continuous optimal play, not under 5).
    private static let stationCurve: [(cost: Double, revenue: Double, cycle: TimeInterval, growth: Double)] = [
        (4,             1,        0.6,  1.18),
        (60,            60,       3,    1.19),
        (720,           540,      6,    1.20),
        (8_640,         4_320,    12,   1.21),
        (103_680,       51_840,   24,   1.22),
        (1_244_160,     622_080,  48,   1.23),
    ]

    /// Levels raised alongside the steeper cost growth above - the old thresholds (10/25/50)
    /// were reachable within the first 20 seconds of MAX-buying, which collapsed cycle time to
    /// the floor almost immediately and made "serve N" quests trivial rather than a target.
    static let milestones: [Milestone] = [
        Milestone(level: 40,   kind: .speed(2)),
        Milestone(level: 100,  kind: .profit(2)),
        Milestone(level: 250,  kind: .speed(2)),
        Milestone(level: 500,  kind: .profit(3)),
        Milestone(level: 1000, kind: .speed(2)),
        Milestone(level: 2000, kind: .profit(4)),
    ]

    /// A station stops getting faster past this point, otherwise cycles underflow the tick.
    static let minimumCycle: TimeInterval = 0.05

    static let managerCostFactor: Double = 500
    /// The first station in a venue is deliberately cheap to staff. At the full factor the
    /// very first manager costs 2,000 against a starting balance of about 100, which put a
    /// wall in front of the player one minute in - and automation is the idea the game most
    /// needs to teach early. It also gets each new venue automating quickly.
    static let firstStationManagerFactor: Double = 60

    // Offline / retention
    static let offlineEfficiency: Double = 0.5
    static let offlineCapHours: Double = 2
    static let offlineCapHoursVIP: Double = 12

    // Prestige
    static let prestigeStarDivisor: Double = 1e12
    static let prestigeStarCoefficient: Double = 150
    static let profitPerStar: Double = 0.02
    /// Below this there is nothing to gain, so the button stays locked.
    static let minimumLifetimeForPrestige: Double = 1e11

    // Entitlements
    static let vipProfitBonus: Double = 0.25

    // MARK: Venues

    static let venues: [VenueSpec] = [
        VenueSpec(id: 0, name: "Burger Shack", tagline: "Where every empire starts", theme: .burger, stations: build([
            ("Fry Basket",         .fries,   ["#F5C242", "#E8873B", "#C0392B"]),
            ("Smash Griddle",      .bun,     ["#D9903F", "#8B4A2B", "#5C9E4A"]),
            ("Soda Fountain",      .cup,     ["#E4453A", "#F7F2E7", "#3B2C26"]),
            ("Hot Dog Roller",     .stick,   ["#E07A4C", "#F3D9A4", "#C0392B"]),
            ("Milkshake Bar",      .cone,    ["#F2B8C6", "#FFF6EA", "#C0392B"]),
            ("Deluxe Combo Tray",  .plate,   ["#F5C242", "#8B4A2B", "#5C9E4A"]),
        ], venue: 0)),

        VenueSpec(id: 1, name: "Sushi Bar", tagline: "Precision pays", theme: .sushi, stations: build([
            ("Miso Bar",           .cup,     ["#8B5E3C", "#F0E4CE", "#4E7A51"]),
            ("Nigiri Counter",     .nigiri,  ["#F4A9A0", "#FBF5EA", "#2E4A3C"]),
            ("Roll Station",       .roll,    ["#2E4A3C", "#FBF5EA", "#E8734A"]),
            ("Tempura Fryer",      .fries,   ["#EBC27A", "#D89A4A", "#8B5E3C"]),
            ("Ramen Pot",          .bowl,    ["#C0503A", "#F3D9A4", "#4E7A51"]),
            ("Omakase Tray",       .plate,   ["#2E4A3C", "#F4A9A0", "#E8C15A"]),
        ], venue: 1)),

        VenueSpec(id: 2, name: "Pizza Piazza", tagline: "Hot, round, profitable", theme: .pizza, stations: build([
            ("Garlic Knots",       .roll,    ["#E0B15E", "#B57A32", "#5C9E4A"]),
            ("Slice Window",       .wedge,   ["#F0C24B", "#D64B32", "#5C9E4A"]),
            ("Soda Cooler",        .cup,     ["#3E7CB1", "#F7F2E7", "#2C3E50"]),
            ("Pasta Pot",          .bowl,    ["#E8B84B", "#C0392B", "#5C9E4A"]),
            ("Calzone Oven",       .wrap,    ["#DBA45C", "#8B4A2B", "#C0392B"]),
            ("Family Feast",       .plate,   ["#D64B32", "#F0C24B", "#2C3E50"]),
        ], venue: 2)),

        VenueSpec(id: 3, name: "Taco Fiesta", tagline: "Turn up the heat", theme: .taco, stations: build([
            ("Chips & Salsa",      .fries,   ["#EBC27A", "#C0392B", "#5C9E4A"]),
            ("Taco Grill",         .wrap,    ["#F1C75B", "#C0392B", "#5C9E4A"]),
            ("Agua Fresca",        .cup,     ["#E8734A", "#FFF3D6", "#2C6E49"]),
            ("Elote Cart",         .stick,   ["#F5D547", "#E0A030", "#5C9E4A"]),
            ("Quesadilla Press",   .wedge,   ["#E8B84B", "#D9903F", "#C0392B"]),
            ("Fiesta Platter",     .plate,   ["#C0392B", "#F5D547", "#2C6E49"]),
        ], venue: 3)),

        VenueSpec(id: 4, name: "Dessert Dream", tagline: "The sweetest margins", theme: .dessert, stations: build([
            ("Cookie Tray",        .roll,    ["#C98A50", "#7A4A28", "#F3E0C7"]),
            ("Cupcake Case",       .cupcake, ["#F5A9C0", "#FFF3E2", "#C0392B"]),
            ("Boba Bar",           .cup,     ["#C9A27E", "#3B2C26", "#F3E0C7"]),
            ("Gelato Cone",        .cone,    ["#9BD4C8", "#E8A5C0", "#D9A15C"]),
            ("Cheesecake Slice",   .wedge,   ["#F6E3A8", "#E8734A", "#F3E0C7"]),
            ("Grand Dessert Tower", .plate,  ["#F5A9C0", "#9BD4C8", "#F5D547"]),
        ], venue: 4)),
    ]

    private static func build(_ rows: [(String, FoodArt, [String])], venue: Int) -> [StationSpec] {
        let costScale = pow(25, Double(venue))
        let revenueScale = pow(30, Double(venue))
        return rows.enumerated().map { index, row in
            let curve = stationCurve[index]
            return StationSpec(
                id: index,
                name: row.0,
                art: row.1,
                colors: row.2,
                baseCost: curve.cost * costScale,
                baseRevenue: curve.revenue * revenueScale,
                baseCycle: curve.cycle,
                costGrowth: curve.growth
            )
        }
    }

    static func venue(_ id: Int) -> VenueSpec { venues[min(max(id, 0), venues.count - 1)] }

    // MARK: Cost curve

    /// Cost of the `n`th purchase counting from an owned level of `level`.
    /// Level 0 means unowned, so the first purchase costs exactly `baseCost`.
    static func cost(spec: StationSpec, level: Int, quantity: Int) -> Double {
        guard quantity > 0 else { return 0 }
        let g = spec.costGrowth
        // Closed-form geometric sum: base·g^level · (g^n − 1)/(g − 1).
        // Looping would be fine at n=10 but Max-buy can run to thousands of levels.
        return spec.baseCost * pow(g, Double(level)) * (pow(g, Double(quantity)) - 1) / (g - 1)
    }

    /// How many levels `coins` can buy, given the same curve. Inverse of `cost`.
    static func maxAffordable(spec: StationSpec, level: Int, coins: Double) -> Int {
        guard coins > 0 else { return 0 }
        let g = spec.costGrowth
        let first = spec.baseCost * pow(g, Double(level))
        guard coins >= first else { return 0 }
        let n = log(coins * (g - 1) / first + 1) / log(g)
        // Floating point can land a hair over the true root; verify before returning.
        var candidate = Int(n.rounded(.down))
        while candidate > 0 && cost(spec: spec, level: level, quantity: candidate) > coins {
            candidate -= 1
        }
        return max(0, candidate)
    }

    static func managerCost(spec: StationSpec) -> Double {
        spec.baseCost * (spec.id == 0 ? firstStationManagerFactor : managerCostFactor)
    }

    // MARK: Milestones

    static func profitMultiplier(level: Int) -> Double {
        milestones.reduce(1.0) { acc, m in
            guard level >= m.level, case .profit(let v) = m.kind else { return acc }
            return acc * v
        }
    }

    static func speedMultiplier(level: Int) -> Double {
        milestones.reduce(1.0) { acc, m in
            guard level >= m.level, case .speed(let v) = m.kind else { return acc }
            return acc * v
        }
    }

    static func nextMilestone(level: Int) -> Milestone? {
        milestones.first { $0.level > level }
    }

    // MARK: Derived station values

    static func cycleTime(spec: StationSpec, level: Int) -> TimeInterval {
        max(minimumCycle, spec.baseCycle / speedMultiplier(level: level))
    }

    /// Payout for one completed cycle, before boosts but after levels and milestones.
    static func revenuePerCycle(spec: StationSpec, level: Int) -> Double {
        guard level > 0 else { return 0 }
        return spec.baseRevenue * Double(level) * profitMultiplier(level: level)
    }

    // MARK: Prestige

    /// Total stars the player's lifetime earnings entitle them to.
    static func totalStars(lifetimeEarnings: Double) -> Int {
        guard lifetimeEarnings > 0 else { return 0 }
        let raw = prestigeStarCoefficient * sqrt(lifetimeEarnings / prestigeStarDivisor)
        guard raw.isFinite else { return Int.max }
        return Int(raw.rounded(.down))
    }

    /// What a reset would award right now.
    static func pendingStars(lifetimeEarnings: Double, currentStars: Int) -> Int {
        max(0, totalStars(lifetimeEarnings: lifetimeEarnings) - currentStars)
    }

    static func starMultiplier(stars: Int) -> Double {
        1 + Double(stars) * profitPerStar
    }

    // MARK: Legacy (second prestige layer)

    /// Reachable only after repeatedly prestiging in the ordinary sense - a first prestige at
    /// the minimum lifetime earnings yields roughly 47 stars, so 500 lifetime stars takes
    /// several trips through the regular loop.
    static let legacyUnlockLifetimeStars = 500

    static func legacyMultiplier(level: Int) -> Double {
        1 + Double(level) * 0.05
    }
}

extension Format {
    /// `2.0` -> `2`, `2.5` -> `2.5`. Keeps milestone labels tidy.
    static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
