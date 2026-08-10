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
    case burger, sushi, pizza, taco, dessert, diner, foodtruck
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
    ///
    /// Retuned repeatedly against simulations of the real engine (see EarlyGamePacingTests,
    /// which pins this): 4_000 put the Sushi Bar under 10 minutes away; 8_000 predated the
    /// golden-customer fixes and measured ~12.5 minutes for a hyperactive player
    /// (frame-perfect combo, optimal build-then-hoard); 16_000 hit ~24 minutes at noon but
    /// dipped under the 20-minute floor during Happy Hour's x1.5 evening window - exactly
    /// when first sessions actually happen. 24_000 holds the floor even there (~23 minutes
    /// worst case in-window, ~34 outside it).
    var unlockCost: Double {
        id == 0 ? 0 : stations[0].baseCost * 24_000
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
    /// The star bonus used to be flat (+2% profit per star, uncapped) - fine near the start,
    /// but it fed a runaway: more stars -> higher permanent profit -> lifetime earnings climb
    /// faster -> the *next* prestige lands sooner too, and because totalStars grows with
    /// sqrt(earnings) while the bonus grew linearly with stars, the two rates canceled out
    /// into a constant time-per-star instead of a slowing one - the loop never decelerated on
    /// its own. A save that legitimately reached this had gone from 16K to ~1.7e19 stars
    /// within the same play session. Square-rooting the bonus (below) makes each further star
    /// cost proportionally more time than the last, same shape as totalStars itself, so the
    /// loop is self-limiting again. Tuned so a prestige at the bare minimum threshold (~47
    /// stars) still lands close to the old flat curve's +94%, and 500 stars is a strong
    /// +300% (4x) - big early payoff, still climbing steadily after, never running away.
    /// (The Legacy gate used to reference this 500 number; it's prestige-count based now -
    /// see `legacyUnlockPrestigeCount`.)
    static let starBonusAtReferenceCount: Double = 3.0
    static let starBonusReferenceCount: Double = 500
    /// Below this there is nothing to gain, so the button stays locked.
    static let minimumLifetimeForPrestige: Double = 1e11

    // Entitlements
    static let vipProfitBonus: Double = 0.25
    /// Mogul Pass, the $49.99 whale permanent. Multiplies WITH VIP (x1.25 x x1.5 = x1.875
    /// for both) - a percentage bonus stays meaningful at any income scale, which is what
    /// makes it whale-proof against the compounding star curve.
    static let mogulProfitBonus: Double = 0.5
    static let mogulOfflineCapBonusHours: Double = 12

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

        // The two twist venues: each teaches a new rule instead of just paying more.
        // The Midnight Diner's stations earn at FULL offline rate (see OfflineEarnings);
        // the Food Truck Rally crowns a rotating Daily Special station at x3 (see
        // `Balance.dailySpecialStation`).
        VenueSpec(id: 5, name: "Midnight Diner", tagline: "Never closes, never sleeps", theme: .diner, stations: build([
            ("Bottomless Coffee",  .cup,     ["#6B4A32", "#F3E0C7", "#3B2C26"]),
            ("Blue Plate Special", .plate,   ["#5B8BD9", "#F7F2E7", "#C0392B"]),
            ("Pancake Stack",      .roll,    ["#E8B84B", "#8B4A2B", "#F6E3A8"]),
            ("Patty Melt Press",   .bun,     ["#D9903F", "#F3D9A4", "#5C9E4A"]),
            ("Pie Case",           .wedge,   ["#C0503A", "#F6E3A8", "#7A4A28"]),
            ("Graveyard Platter",  .plate,   ["#3E4A6B", "#F3D9A4", "#E4453A"]),
        ], venue: 5)),

        VenueSpec(id: 6, name: "Food Truck Rally", tagline: "Follow the crowd", theme: .foodtruck, stations: build([
            ("Street Corn Cart",   .stick,   ["#F5D547", "#E07A3C", "#5C9E4A"]),
            ("Smash Burger Truck", .bun,     ["#E4453A", "#F3D9A4", "#3B2C26"]),
            ("Banh Mi Window",     .wrap,    ["#F0E4CE", "#C0503A", "#5C9E4A"]),
            ("Poke Bowl Stand",    .bowl,    ["#F4A9A0", "#2E4A3C", "#F5D547"]),
            ("Churro Fryer",       .fries,   ["#D9A15C", "#C98A50", "#F5A9C0"]),
            ("Fusion Feast Truck", .plate,   ["#5BD6E8", "#E4453A", "#F5D547"]),
        ], venue: 6)),
    ]

    /// The Food Truck Rally's Daily Special: one of its six stations pays x3 today,
    /// rotating by calendar day - a reason to visit the rally every single day.
    static func dailySpecialStation(day: Int) -> Int {
        ((day % 6) + 6) % 6
    }

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

    // MARK: Staleness (organic-growth cap)

    /// Hours a fresh board gets before the staleness tax below starts - long enough that even
    /// an unhurried first-time player (simulated at ~9h to their first Franchise) reaches it
    /// before ever paying this, so it never touches a brand new save.
    static let staleGraceHours: Double = 8
    /// Scales how many "tax days" one real hour past the grace period counts as.
    static let staleDaysPerHour: Double = 1.0 / 6.0
    static let stalePower: Double = 3.0

    /// Every purchase on the SAME board (stations, managers, venue unlocks) gets
    /// proportionally pricier the longer that board goes without a Franchise or Legacy reset.
    ///
    /// A single station's cost curve already compounds forever on its own, and with thirty
    /// stations across five venues all drawing from one shared, ever-growing income pool, the
    /// portfolio as a whole compounds faster still - simulated against the real curves, a
    /// player who simply never resets out-earns *every* Franchise cadence tested, at every
    /// checkpoint from a day out to a week, which made "never prestige" the strictly correct
    /// answer instead of prestige being a real decision. This tax targets exactly that: it
    /// only starts after `staleGraceHours` (well past even a slow first Franchise, verified by
    /// simulation not to change that number), then grows with the cube of days spent stalling
    /// past that point. By day 3-7 a patient Franchise cadence clearly out-earns refusing to
    /// reset, while resetting too often is still roughly a wash against not resetting at all -
    /// there's a real cadence to find, not just an "always" or "never" answer.
    /// `graceBonusHours` shifts when the tax begins without touching its curve - Legacy's
    /// Slow Cooker perk adds hours, the High Roller contract subtracts them. The floor
    /// keeps a stacked debuff from ever taxing a literally brand-new board.
    static func stalenessMultiplier(boardAgeHours: Double, graceBonusHours: Double = 0) -> Double {
        let grace = max(2, staleGraceHours + graceBonusHours)
        guard boardAgeHours > grace else { return 1 }
        let daysPast = (boardAgeHours - grace) * staleDaysPerHour
        return pow(1 + daysPast, stalePower)
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

    /// A ceiling no legitimate trajectory could reach. Re-derived in the August review:
    /// the original 100M figure came from a simulation that predates the final staleness
    /// constants and modeled no research feedback - re-simulated against the shipped
    /// formulas, a hardcore player legitimately reaches ~200-250M lifetime stars inside
    /// six months, which the old ceiling would have CLAMPED. 1e10 sits ~50x above that
    /// six-month hardcore trajectory (star growth decelerates sharply after, so even years
    /// of play stay far below it) while remaining nine orders of magnitude under the
    /// Int64 conversion trap line the ceiling exists to guard.
    ///
    /// This exists because of a real incident: a since-fixed linear (not sqrt-scaled) star
    /// bonus let a compounding loop push a live save's lifetime stars into the 1e19 range
    /// within a single session - large enough that converting the raw `Double` below to `Int`
    /// would **trap and crash the app outright**, on every launch, the instant any view
    /// (the HUD included) computed `pendingStars`. That crash happens deep inside a SwiftUI
    /// computed property and isn't something a decode-error catch block can recover from -
    /// `Int(aDoubleTooLargeToFit)` is a fatal runtime trap, not a throwable error.
    ///
    /// `totalStars` below refuses to ever compute past this ceiling, and `GameState`'s
    /// decoder clamps any save that already has more back down to it - so a save already
    /// hit by the old bug becomes safe and playable again (with a still-enormous but sane
    /// permanent bonus) instead of crash-looping forever, and the same failure mode can't
    /// recur even if some future change reopens unbounded growth.
    static let maxSaneLifetimeStars = 10_000_000_000

    /// The lifetime-earnings figure that maps to `maxSaneLifetimeStars` under the formula
    /// below - derived, not hardcoded, so it can never drift out of sync with `totalStars`.
    static var maxSaneLifetimeEarnings: Double {
        let stars = Double(maxSaneLifetimeStars) / prestigeStarCoefficient
        return prestigeStarDivisor * stars * stars
    }

    /// Total stars the player's lifetime earnings entitle them to.
    static func totalStars(lifetimeEarnings: Double) -> Int {
        guard lifetimeEarnings > 0 else { return 0 }
        let raw = prestigeStarCoefficient * sqrt(lifetimeEarnings / prestigeStarDivisor)
        // Comparing as Doubles is always safe, however large `raw` is - it's only the
        // Double -> Int conversion below that can trap, so nothing unbounded ever reaches it.
        guard raw.isFinite, raw < Double(maxSaneLifetimeStars) else { return maxSaneLifetimeStars }
        return Int(raw.rounded(.down))
    }

    /// What a reset would award right now.
    static func pendingStars(lifetimeEarnings: Double, currentStars: Int) -> Int {
        max(0, totalStars(lifetimeEarnings: lifetimeEarnings) - currentStars)
    }

    static func starMultiplier(stars: Int) -> Double {
        guard stars > 0 else { return 1 }
        return 1 + starBonusAtReferenceCount * sqrt(Double(stars) / starBonusReferenceCount)
    }

    // MARK: Legacy (second prestige layer)

    /// Gated on prestige COUNT, not stars: real first-prestige awards run ~10-15K stars
    /// (players wait well past the 1e11 minimum), so the old 500-lifetime-star gate was
    /// crossed on the very first Franchise - "several trips through the regular loop"
    /// stopped being true the moment the award curve was measured. Five franchises lands
    /// around week 3-5 of the intended 3-7 day cadence.
    static let legacyUnlockPrestigeCount = 5

    /// +20% per level. Raised from +5% in the same pass that made `legacyReset()` zero
    /// `lifetimeEarnings`: now that a Legacy genuinely restarts the star climb (instead of
    /// one quick re-prestige restoring the whole multiplier), the permanent bonus has to
    /// be worth what's actually being given up.
    static func legacyMultiplier(level: Int) -> Double {
        1 + Double(level) * 0.20
    }

    // MARK: Research pricing

    /// Interactive perk choices per franchise run. Playtest feedback: with thirty stations
    /// each crossing three-plus choice milestones, perk sheets fired constantly - over a
    /// hundred per patient run. Four per run turns the system inside out: instead of a
    /// chore, "which four stations get a personal build this run?" is a strategy decision
    /// that pairs with the run's Contract. Milestone auto-bonuses are untouched.
    static let perkChoicesPerRun = 4

    /// Deep research ranks cost this fraction of the player's latest Franchise award (with
    /// the static curve in `ResearchNode.cost` as a floor). Award-proportional pricing is
    /// what makes the tree calendar-paced instead of wealth-paced: star income compounds so
    /// hard that ANY fixed price is trivial one board later (the full static tree fell in
    /// under two weeks in every simulated profile). At 0.4, each Franchise funds ~2-3
    /// ranks, and the 90-rank tree maxes at day ~111/185/259 for a 3/5/7-day prestige
    /// cadence - centered on the intended ~6 months - identically across a 10x spread of
    /// play intensity, because the award scales with the player. Pinned to the last
    /// completed award (not live pendingStars) so waiting or timing purchases can't game it.
    static let researchAwardCostFraction = 0.4
}

extension Format {
    /// `2.0` -> `2`, `2.5` -> `2.5`. Keeps milestone labels tidy.
    static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
