import Foundation

/// What an achievement actually measures. Every case reads off state that already exists
/// elsewhere in the save - achievements are a lens on existing progress, not a new ledger.
enum AchievementMetric: Equatable {
    case lifetimeEarnings
    case customersServed
    case taps
    case managersOwned
    case legendaryManagers
    case venuesUnlocked
    case leagueTier
    case prestiges
}

struct AchievementSpec: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let metric: AchievementMetric
    let threshold: Double
    let rewardGems: Int
    let symbol: String

    /// How the threshold reads in the UI - currency for money, plain counts otherwise.
    var thresholdLabel: String {
        switch metric {
        case .lifetimeEarnings: return Format.currency(threshold)
        case .leagueTier: return LeagueTier(rawValue: Int(threshold))?.name ?? ""
        default: return Format.count(Int(threshold))
        }
    }
}

enum AchievementCatalog {

    static let all: [AchievementSpec] = [
        // Lifetime earnings
        AchievementSpec(id: "earn_1", title: "First Fortune", detail: "Earn \(Format.currency(100_000)) lifetime",
                        metric: .lifetimeEarnings, threshold: 100_000, rewardGems: 15, symbol: "dollarsign.circle.fill"),
        AchievementSpec(id: "earn_2", title: "Big Money", detail: "Earn \(Format.currency(10_000_000)) lifetime",
                        metric: .lifetimeEarnings, threshold: 10_000_000, rewardGems: 45, symbol: "dollarsign.circle.fill"),
        // Rescaled in the August review: the old 1e9 threshold cleared two orders of
        // magnitude before the first prestige was even possible (minimum 1e11), so the
        // whole tier was done pre-prestige. 1e13 lands shortly after the first Franchise.
        //
        // Dynasty (earn_4, below) was meant to be the six-month-arc capstone tier, matching
        // prestige_4's 40-Franchise capstone - but tracing it through the CURRENT star/
        // earnings formula (totalStars = 150*sqrt(earnings/1e12), and lifetimeStars tracks
        // cumulative lifetimeEarnings 1:1 for a steadily-playing account since prestige()
        // never resets it) shows 1e18 corresponds to only ~150,000 cumulative stars - about
        // 10-15x a single FIRST prestige's award (Balance.legacyUnlockPrestigeCount's doc
        // comment cites ~10-15K for that one award alone). At the documented 3-7 day
        // cadence that's crossed within the first few weeks, not six months - the same
        // compounding-feedback drift Research pricing and Legacy's own gate already had to
        // be moved off of. Left as-is pending a real decision: raise the threshold to
        // actually match the capstone (~1e24, derived from the ~225M-star six-month
        // benchmark `Balance.maxSaneLifetimeStars` cites), or keep Dynasty as an earlier,
        // more attainable achievement and stop claiming parity with prestige_4.
        AchievementSpec(id: "earn_3", title: "Tycoon", detail: "Earn \(Format.currency(1e13)) lifetime",
                        metric: .lifetimeEarnings, threshold: 1e13, rewardGems: 120, symbol: "dollarsign.circle.fill"),
        AchievementSpec(id: "earn_4", title: "Dynasty", detail: "Earn \(Format.currency(1e18)) lifetime",
                        metric: .lifetimeEarnings, threshold: 1e18, rewardGems: 250, symbol: "dollarsign.circle.fill"),

        // Customers served
        AchievementSpec(id: "serve_1", title: "Lunch Rush", detail: "Serve 10,000 customers",
                        metric: .customersServed, threshold: 10_000, rewardGems: 15, symbol: "takeoutbag.and.cup.and.straw.fill"),
        AchievementSpec(id: "serve_2", title: "Packed House", detail: "Serve 250,000 customers",
                        metric: .customersServed, threshold: 250_000, rewardGems: 45, symbol: "takeoutbag.and.cup.and.straw.fill"),
        AchievementSpec(id: "serve_3", title: "Legend of the Line", detail: "Serve 5,000,000 customers",
                        metric: .customersServed, threshold: 5_000_000, rewardGems: 120, symbol: "takeoutbag.and.cup.and.straw.fill"),

        // Taps
        AchievementSpec(id: "tap_1", title: "Quick Hands", detail: "Tap 1,000 times",
                        metric: .taps, threshold: 1_000, rewardGems: 15, symbol: "hand.tap.fill"),
        AchievementSpec(id: "tap_2", title: "Tap Machine", detail: "Tap 25,000 times",
                        metric: .taps, threshold: 25_000, rewardGems: 45, symbol: "hand.tap.fill"),
        AchievementSpec(id: "tap_3", title: "Carpal Tunnel Club", detail: "Tap 250,000 times",
                        metric: .taps, threshold: 250_000, rewardGems: 120, symbol: "hand.tap.fill"),

        // Managers owned
        AchievementSpec(id: "staff_1", title: "Building a Team", detail: "Own 10 managers",
                        metric: .managersOwned, threshold: 10, rewardGems: 15, symbol: "person.2.fill"),
        AchievementSpec(id: "staff_2", title: "Full Roster", detail: "Own 25 managers",
                        metric: .managersOwned, threshold: 25, rewardGems: 45, symbol: "person.2.fill"),
        AchievementSpec(id: "staff_3", title: "Empire of Staff", detail: "Own 50 managers",
                        metric: .managersOwned, threshold: 50, rewardGems: 120, symbol: "person.2.fill"),

        // Legendary managers
        AchievementSpec(id: "legend_1", title: "Star Power", detail: "Own 1 Legendary manager",
                        metric: .legendaryManagers, threshold: 1, rewardGems: 15, symbol: "star.circle.fill"),
        AchievementSpec(id: "legend_2", title: "All-Star Kitchen", detail: "Own 3 Legendary managers",
                        metric: .legendaryManagers, threshold: 3, rewardGems: 45, symbol: "star.circle.fill"),
        AchievementSpec(id: "legend_3", title: "Hall of Fame", detail: "Own 6 Legendary managers",
                        metric: .legendaryManagers, threshold: 6, rewardGems: 120, symbol: "star.circle.fill"),

        // Venues
        AchievementSpec(id: "venue_1", title: "Expanding", detail: "Unlock 2 venues",
                        metric: .venuesUnlocked, threshold: 2, rewardGems: 15, symbol: "map.fill"),
        AchievementSpec(id: "venue_2", title: "Almost There", detail: "Unlock 4 venues",
                        metric: .venuesUnlocked, threshold: 4, rewardGems: 45, symbol: "map.fill"),
        AchievementSpec(id: "venue_3", title: "Full Franchise", detail: "Unlock 5 venues",
                        metric: .venuesUnlocked, threshold: 5, rewardGems: 120, symbol: "map.fill"),
        AchievementSpec(id: "venue_4", title: "The Whole Court", detail: "Unlock all 7 venues",
                        metric: .venuesUnlocked, threshold: 7, rewardGems: 250, symbol: "map.fill"),

        // League
        AchievementSpec(id: "league_1", title: "Silver Standing", detail: "Reach the Silver league",
                        metric: .leagueTier, threshold: Double(LeagueTier.silver.rawValue), rewardGems: 15, symbol: "trophy.fill"),
        AchievementSpec(id: "league_2", title: "Golden Table", detail: "Reach the Gold league",
                        metric: .leagueTier, threshold: Double(LeagueTier.gold.rawValue), rewardGems: 45, symbol: "trophy.fill"),
        AchievementSpec(id: "league_3", title: "Diamond Elite", detail: "Reach the Diamond league",
                        metric: .leagueTier, threshold: Double(LeagueTier.diamond.rawValue), rewardGems: 120, symbol: "trophy.fill"),

        // Prestige
        AchievementSpec(id: "prestige_1", title: "Fresh Start", detail: "Franchise once",
                        metric: .prestiges, threshold: 1, rewardGems: 15, symbol: "arrow.triangle.2.circlepath"),
        AchievementSpec(id: "prestige_2", title: "Serial Founder", detail: "Franchise 5 times",
                        metric: .prestiges, threshold: 5, rewardGems: 45, symbol: "arrow.triangle.2.circlepath"),
        AchievementSpec(id: "prestige_3", title: "Franchise Master", detail: "Franchise 15 times",
                        metric: .prestiges, threshold: 15, rewardGems: 120, symbol: "arrow.triangle.2.circlepath"),
        // 40 franchises at the intended 3-7 day cadence is roughly the six-month arc's
        // finish line - the prestige track's capstone. earn_4 above was meant to match this
        // but currently lands far earlier - see its own doc comment.
        AchievementSpec(id: "prestige_4", title: "Food Court Legend", detail: "Franchise 40 times",
                        metric: .prestiges, threshold: 40, rewardGems: 250, symbol: "arrow.triangle.2.circlepath"),
    ]

    private static let index: [String: AchievementSpec] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func spec(_ id: String) -> AchievementSpec? { index[id] }
}

enum Achievements {

    static func progress(_ spec: AchievementSpec, state: GameState) -> Double {
        switch spec.metric {
        case .lifetimeEarnings: return state.lifetimeEarnings
        case .customersServed: return Double(state.totalServed)
        case .taps: return Double(state.totalTaps)
        case .managersOwned: return Double(state.managers.count)
        case .legendaryManagers:
            return Double(state.managers.filter { $0.spec.rarity == .legendary }.count)
        case .venuesUnlocked: return Double(state.venues.filter(\.unlocked).count)
        case .leagueTier: return Double(state.bestLeagueTierReached.rawValue)
        case .prestiges: return Double(state.prestigeCount)
        }
    }

    static func isComplete(_ spec: AchievementSpec, state: GameState) -> Bool {
        progress(spec, state: state) >= spec.threshold
    }

    static func fraction(_ spec: AchievementSpec, state: GameState) -> Double {
        guard spec.threshold > 0 else { return 1 }
        return min(1, progress(spec, state: state) / spec.threshold)
    }
}
