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
    /// which pins this): 4_000 -> 8_000 -> 16_000 -> 24_000, each round fixing a specific
    /// undercounted income source (golden customers, the combo cap, Coffee Break). 24_000
    /// still measured "safe" at ~27.5 minutes - except `simulateFreshInstall` only ever
    /// tapped 2 of the 6 stations while still spending coins leveling all 6, so those other
    /// four produced nothing in the sim despite a real player obviously tapping everything
    /// they own. Live reports of the Sushi Bar opening in 6-7 minutes on genuinely fresh
    /// saves (with the debug menu confirmed untouched) matched almost exactly once the sim
    /// was fixed to tap all six - 24_000 was never actually safe, the test just couldn't see
    /// it. The base then came down from 280_000 to 110_000 when `venueEscalation` below
    /// took over the job of pricing the DEEPER venues - the two are tuned as a pair, so
    /// neither number means much on its own.
    ///
    /// Worst case (hyperactive, Happy Hour, everything redeemed on cooldown) measures
    /// ~30 minutes to the Sushi Bar; the steadier long-horizon sim, which also spends coins
    /// hiring managers, puts it nearer 37.
    var unlockCost: Double {
        guard id > 0 else { return 0 }
        let raw = stations[0].baseCost * 110_000 * pow(Self.venueEscalation, Double(id - 1))
        // The last venue's step measured disproportionately steeper than every step before
        // it - a real engine simulation showed opening it alone eating 33-47% of an entire
        // prestige cycle's total time, every cycle, while the venue-to-venue gaps leading up
        // to it grew smoothly. venueEscalation itself is uniform by design (see its own doc
        // comment - later venues SHOULD cost more, on purpose), so this is a discount on just
        // the final step rather than a change to the arc's shape. -30% matches the rounding
        // this game already uses for faucet/sink adjustments elsewhere (quests -50%,
        // achievements -30%, festival -40%, daily -35%, league -35%).
        guard id == Balance.venues.count - 1 else { return raw }
        return raw * 0.7
    }

    /// Extra cost escalation per venue, ON TOP of the 25x/venue scale `baseCost` already
    /// carries.
    ///
    /// At 1.0 every venue takes about the same real time to reach - the 25x cost and 25x
    /// revenue scales cancel out - which is exactly what the first full seven-venue
    /// measurement showed: gaps of 28/29/23/21/23/22 minutes, roughly flat with the back
    /// half slightly FASTER than the front. Above 1.0 each venue costs progressively more
    /// relative to what the board earns, so the arc slopes upward: later venues become
    /// bigger commitments rather than quicker ones, which is the shape that pushes a
    /// plateauing player toward prestige instead of pressing deeper forever.
    ///
    /// Measured candidates (long-horizon sim, first four venue gaps):
    ///   1.0  ->  28 / 29 / 23 / 21   (flat, then faster - the reported problem)
    ///   1.5  ->  50 / 50 / 54        (slope appears, but the whole arc runs long)
    ///   2.2  ->  37 / 39 / 31 / 72   (clear upward trend, ~5h+ to the last venue)
    ///
    /// 1.8 splits those: a real upward slope with the full arc still inside a long session.
    /// Adjacent values can't honestly be told apart from single runs - quest, festival and
    /// milestone timing swing individual gaps by more than the difference between them
    /// (note the 31-then-72 pair above), so this is a defensible setting rather than a
    /// precisely optimal one. Real play is the arbiter.
    static let venueEscalation: Double = 1.8

    /// Deeper venues pay far more and cost far more - this is what makes moving on feel
    /// like a jump rather than a grind extension. The two used mismatched bases (30 vs
    /// 25), which reads as a flavor choice but is actually a structural accelerant: since
    /// revenue compounds faster than cost, every subsequent venue is mathematically MORE
    /// profit-efficient than the last (venue 1 pays back 1.2x more per coin invested than
    /// venue 0, venue 6 pays back nearly 3x more) - a real 2-hour engine simulation
    /// confirmed the result exactly, each venue taking noticeably less real time than the
    /// one before it (21m/17m/10m/6.5m/4.5m/3.5m, Burger through Food Truck), matching a
    /// live report of Burger Shack taking ~10 minutes and Sushi clearing in about half
    /// that. Same base now: venues still cost more and pay more in absolute terms (the
    /// "jump" the original comment wanted), but the RATIO between them - what actually
    /// governs how long a venue takes - stays flat instead of compounding.
    var revenueMultiplier: Double { pow(25, Double(id)) }
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
    //
    // Raised again (+0.05/station) after a live report of the wider economy still running
    // ~2x too fast even past the early game - confirmed by simulateLongHorizon
    // (EarlyGamePacingTests), which showed a fully-engaged player still reaching each new
    // venue in a clean, roughly-halving cadence under the old curve. This alone doesn't
    // flatten the SIZE of each venue-to-venue jump (that's VenueSpec's shared 25x/venue
    // scale, a separate, deliberately-unequal-feeling lever - see its own doc comment) -
    // it slows how fast a player climbs the levels WITHIN a venue, which is what actually
    // governs overall pace. Re-simulated against the real engine: roughly 40-45% slower
    // across the board (Sushi Bar opening moved from ~22 to ~32 minutes of continuous
    // engaged play in the long-horizon sim).
    //
    // Raised again (+0.06/station) alongside VenueSpec.unlockCost's own retune: the level-40
    // speed milestone, meant to land ~5 minutes in, was actually being crossed under 2
    // minutes once EarlyGamePacingTests' sim was fixed to tap all 6 stations instead of 2
    // (see unlockCost's doc comment). This alone barely moved the needle on its own though -
    // a hyperactively-tapped board's income is dominated by SIX stations compounding
    // together, not any one station's own growth rate, so steepening it further has
    // diminishing returns as a standalone lever. It stays paired with the unlockCost raise
    // rather than replacing it.
    private static let stationCurve: [(cost: Double, revenue: Double, cycle: TimeInterval, growth: Double)] = [
        (4,             1,        0.6,  1.29),
        (60,            60,       3,    1.30),
        (720,           540,      6,    1.31),
        (8_640,         4_320,    12,   1.32),
        (103_680,       51_840,   24,   1.33),
        (1_244_160,     622_080,  48,   1.34),
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

    /// The first station in a venue is deliberately cheap to staff. At the full factor the
    /// very first manager costs 2,000 against a starting balance of about 100, which put a
    /// wall in front of the player one minute in - and automation is the idea the game most
    /// needs to teach early. It also gets each new venue automating quickly.
    static let firstStationManagerFactor: Double = 60

    /// Every other station was a flat `baseCost * 500` - and baseCost itself already jumps
    /// roughly an order of magnitude per station by design, so that flat multiplier
    /// compounded the jump instead of taming it: the Burger Shack's last station reached
    /// 622M to staff while the Sushi Bar's first two stations cost 6K and 750K - a gap so
    /// wide the LATER stations of the FIRST venue cost more than the EARLY stations of the
    /// NEXT one, backwards from what "deeper venues cost more" should feel like. Raising
    /// baseCost to a fractional power before scaling tempers that compounding without
    /// touching the stations' own buy-in cost curve (nobody complained about that) - the
    /// last Burger Shack station now runs about 32M, ~19x less, and the curve within any
    /// venue steps up roughly 6x per station instead of 12x.
    static let managerCostExponent: Double = 0.72
    static let managerCostScale: Double = 1_311.2

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
    /// Below this there is nothing to gain, so the button stays locked. Only ever gates the
    /// FIRST prestige - lifetimeEarnings never resets, so every prestige after that is
    /// already past it, gated purely by pendingStars > 0.
    ///
    /// Was 1e11, which a live report caught landing almost exactly at the third venue
    /// opening - a fully-engaged player was still deep in the multi-venue buildout phase
    /// (each venue jumps lifetime earnings ~25-36x on its own) right as the "you can
    /// prestige now" nudge first appeared, so pendingStars kept visibly exploding for many
    /// minutes after. 1e13 (100x higher) lands first eligibility past venue 4 instead,
    /// closer to where a run has more to show for itself - still not perfectly stable
    /// (nothing short of ending active play is, while venues keep coming online), but a
    /// meaningfully less volatile place for the decision to first present itself, and
    /// ~474 pending stars at first sight instead of ~47 - a number that itself reads as
    /// the milestone it's meant to be.
    static let minimumLifetimeForPrestige: Double = 1e13

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
        // Same base as costScale - see VenueSpec.revenueMultiplier's doc comment for why a
        // mismatched 30 here was a structural, compounding accelerant across venues, not a
        // harmless flavor difference.
        let revenueScale = pow(25, Double(venue))
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
        spec.id == 0
            ? spec.baseCost * firstStationManagerFactor
            : managerCostScale * pow(spec.baseCost, managerCostExponent)
    }

    // MARK: Staleness (organic-growth cap)

    /// Hours a fresh board gets before the staleness tax below starts. Raised from 8h to a
    /// full wall-clock week after a real player's board looked stale-taxed well before they'd
    /// had a realistic chance to franchise again - 8 hours punished anyone who simply plays in
    /// sessions longer than a workday. A week comfortably covers even a slow, patient cadence
    /// (see `stalenessMultiplier`'s doc comment for the growth curve past this point) while
    /// still never touching a brand new save.
    static let staleGraceHours: Double = 24 * 7
    /// One real hour past grace counts as this fraction of a "stale week" - i.e. the tax
    /// takes a full wall-clock week past the grace period to complete one step of its curve.
    static let staleWeeksPerHour: Double = 1.0 / (24 * 7)
    /// Linear: each additional wall-clock week past the grace period adds another +100% to
    /// the tax (week 1 past grace = +100%, week 2 = +200%, ...). Was 1.5 (super-linear) on a
    /// curve that reached tens-of-thousands-of-x within a single week of stalling on top of
    /// only an 8-hour grace - a real engine simulation of grinding one venue toward Gold
    /// Mastery (every station at level 250, see `GameEngine.masteryThresholds`) found the
    /// board froze solid under that curve and stayed frozen through 10 more days of
    /// continuous optimal play. Flattening to a strict 1.0 (linear) power, on top of the much
    /// longer grace period above, keeps the tax an honest, predictable long-run nudge instead
    /// of a wall reached within a single evening - it still never flattens out entirely, it
    /// just no longer accelerates.
    static let stalePower: Double = 1.0

    /// Every purchase on the SAME board (stations, managers, venue unlocks) gets
    /// proportionally pricier the longer that board goes without a Franchise or Legacy reset.
    ///
    /// A single station's cost curve already compounds forever on its own, and with thirty
    /// stations across five venues all drawing from one shared, ever-growing income pool, the
    /// portfolio as a whole compounds faster still - simulated against the real curves, a
    /// player who simply never resets out-earns *every* Franchise cadence tested, at every
    /// checkpoint from a day out to a week, which made "never prestige" the strictly correct
    /// answer instead of prestige being a real decision. This tax targets exactly that: it
    /// only starts after `staleGraceHours` (a full wall-clock week - well past even a slow
    /// first Franchise), then grows linearly (`stalePower`) at `staleWeeksPerHour` past that
    /// point, reaching exactly +100% (a 2x multiplier) after one more full wall-clock week
    /// stalling past grace, and another +100% for every wall-clock week after that - gently
    /// enough that a patient Franchise cadence still wins out over refusing to reset, just
    /// over a timescale of weeks rather than hours, leaving room for legitimate same-board
    /// investment like a Mastery grind to actually finish. `graceBonusHours` shifts when the
    /// tax begins without touching its curve - Legacy's Slow Cooker perk adds hours, the High
    /// Roller contract subtracts them. The floor keeps a stacked debuff from ever taxing a
    /// literally brand-new board.
    static func stalenessMultiplier(boardAgeHours: Double, graceBonusHours: Double = 0) -> Double {
        let grace = max(2, staleGraceHours + graceBonusHours)
        guard boardAgeHours > grace else { return 1 }
        let weeksPast = (boardAgeHours - grace) * staleWeeksPerHour
        return pow(1 + weeksPast, stalePower)
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

    /// A ceiling meant to guard against Int64-trapping corruption, not to bound legitimate
    /// play. Re-derived a second time after a real support case: a genuine long-lived,
    /// heavily-compounded save (10.0B lifetime stars, ~4.4e27 lifetime earnings, a x13K+
    /// permanent bonus) organically crossed the old 1e10/~4.4e27 ceiling from the August
    /// review, which assumed a hardcore six-month trajectory tops out ~50x below it. The
    /// decoder's repair path (see `GameState.init(from:)`) then clamped `lifetimeStars`
    /// down to that ceiling on load, at which point `totalStars(lifetimeEarnings:)` could
    /// never again exceed `lifetimeStars` - `pendingStars` was permanently stuck at 0 and
    /// Franchise was permanently disabled, even though the player kept earning normally.
    /// The six-month estimate undersold how far dedicated/idle play compounds past that
    /// window, so this raises the ceiling 10,000x to 1e14, comfortably clear of any
    /// realistic trajectory while staying ~5 orders of magnitude under the Int64
    /// conversion trap line the ceiling exists to guard.
    ///
    /// This mechanism exists because of an earlier, genuinely corrupt incident: a
    /// since-fixed linear (not sqrt-scaled) star bonus let a compounding loop push a live
    /// save's lifetime stars into the 1e19 range within a single session - large enough
    /// that converting the raw `Double` below to `Int` would **trap and crash the app
    /// outright**, on every launch, the instant any view (the HUD included) computed
    /// `pendingStars`. That crash happens deep inside a SwiftUI computed property and
    /// isn't something a decode-error catch block can recover from - `Int(aDoubleTooLargeToFit)`
    /// is a fatal runtime trap, not a throwable error. 1e14 is still five orders of
    /// magnitude below that 1e19 corruption case, so the repair path still catches it.
    ///
    /// `totalStars` below refuses to ever compute past this ceiling, and `GameState`'s
    /// decoder clamps any save that already has more back down to it - so a save already
    /// hit by the old bug becomes safe and playable again (with a still-enormous but sane
    /// permanent bonus) instead of crash-looping forever, and the same failure mode can't
    /// recur even if some future change reopens unbounded growth. A legitimate save can
    /// still in principle reach this higher ceiling given enough time; if that ever
    /// happens again, raise it further rather than assuming corruption.
    static let maxSaneLifetimeStars = 100_000_000_000_000

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
