import Foundation

/// The hard-currency sinks. Every gem the player buys or earns has somewhere to go, which
/// is what makes the currency worth having in the first place.
struct GemOffer: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let cost: Int
    let symbol: String

    static let all: [GemOffer] = [
        GemOffer(id: "boost", title: "Double Profit",
                 subtitle: "×2 on everything for 1 hour", cost: 50, symbol: "bolt.fill"),
        // "Instant Manager" (auto-picks the cheapest unstaffed station) and "Start Rush
        // Hour" used to have Shop cards here too, at these same prices - cut as exact
        // duplicates of purchases already reachable elsewhere at the identical cost: the
        // per-station "hire with gems" button (StationListView, contextual - no auto-picker
        // needed) and the stage's own Rush Hour button (RootView, where its cooldown is
        // already visible). See `GemSpend.hireManagerWithGems` and `startRush` respectively -
        // neither changed, only the redundant Shop-side doors to them came out.
        GemOffer(id: "timewarp", title: "Time Warp",
                 subtitle: "Collect 4 hours of income now", cost: 150, symbol: "clock.arrow.circlepath"),
        GemOffer(id: "instant", title: "Serve Everyone",
                 subtitle: "Finish every station's cycle instantly", cost: 20, symbol: "hand.tap.fill"),
        GemOffer(id: "automate", title: "Automate Venue",
                 subtitle: "Staff every open station here at once", cost: 400, symbol: "person.3.fill"),
        GemOffer(id: "reserve", title: "Chef's Reserve",
                 subtitle: "×3 profit for 3 hours", cost: 300, symbol: "flame.fill"),
        GemOffer(id: "tickets", title: "Ticket Bundle",
                 subtitle: "+500 festival tickets", cost: 150, symbol: "ticket.fill"),
        GemOffer(id: "freeze", title: "Streak Freeze",
                 subtitle: "Protects your login streak for one missed day", cost: 60, symbol: "snowflake"),
        // Renamed from "Research Boost" - it sat next to the real-money "Research Grant"
        // with a near-identical name and nothing distinguishing "this costs gems" from
        // "this costs dollars". Priced below Automate Venue (its value is far smaller) and
        // scaled to the player's latest Franchise so it never becomes a rounding error.
        GemOffer(id: "research", title: "Star Infusion",
                 subtitle: "Research stars - 15% of your last Franchise", cost: 250, symbol: "flask.fill"),
    ]

    /// What the shop actually displays - cheapest first, so the list reads as a ladder
    /// instead of whatever order they happened to be declared in above.
    static var allSortedByCost: [GemOffer] { all.sorted { $0.cost < $1.cost } }

    /// One sink per day at 30% off, rotating deterministically through the catalog by day
    /// number - same deal for everyone on a given day, a fresh reason to open the shop
    /// tomorrow, zero new content. The returned offer carries the discounted cost, so
    /// `GemSpend.redeem` charges the deal price with no special casing.
    static func dailyDeal(now: Date, calendar: Calendar = .current) -> GemOffer {
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let base = allSortedByCost[day % allSortedByCost.count]
        return GemOffer(id: base.id, title: base.title, subtitle: base.subtitle,
                        cost: Int((Double(base.cost) * 0.7).rounded()), symbol: base.symbol)
    }
}

enum GemSpendResult: Equatable {
    case success(String)
    case insufficientGems
    case nothingToDo(String)
}

@MainActor
enum GemSpend {

    static func redeem(_ offer: GemOffer, engine: GameEngine) -> GemSpendResult {
        switch offer.id {
        case "boost":
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            engine.addBoost(id: "gem-boost", label: "×2 Profit", multiplier: 2, hours: 1)
            return .success("Double profit for 1 hour")

        case "timewarp":
            let preview = OfflineEarnings.automatedIncomePerSecond(engine.state)
            guard preview > 0 else {
                return .nothingToDo("Hire a manager first - there's nothing running to fast-forward")
            }
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            let earned = engine.timeWarp(hours: 4)
            return .success("Collected \(Format.currency(earned))")

        case "instant":
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            let earned = engine.instantCompleteAll()
            return .success("Served everyone for \(Format.currency(earned))")

        case "automate":
            // Deliberately NOT scaled by the staleness tax, unlike coin hires: gems buying
            // a way around part of the tax's pressure is a monetization valve the tax was
            // priced with in mind - the tax's real job (making "never franchise" lose) is
            // done by station and unlock costs, which gems can't touch.
            let venue = engine.state.currentVenue
            guard engine.hasUnstaffedStation(venue: venue) else {
                return .nothingToDo("This venue is already fully staffed")
            }
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            engine.grantManagerPack(venue: venue)
            return .success("Every station here is staffed")

        case "reserve":
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            engine.addBoost(id: "chefs-reserve", label: "×3 Chef's Reserve", multiplier: 3, hours: 3)
            return .success("Triple profit for 3 hours")

        case "tickets":
            // Tickets otherwise have no gem-purchasable path at all - a player who is close
            // to a tier near season's end and out of time has nowhere to go. Deliberately
            // priced so it tops up the stretch run rather than buying a whole season: at
            // 150 gems for 500 tickets, covering all ~6,900 needed for tier 30 would take
            // roughly 14 purchases.
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            engine.awardTickets(500)
            return .success("+500 festival tickets")

        case "freeze":
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            engine.addStreakFreeze()
            return .success("Streak Freeze ready")

        case "research":
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            let stars = engine.researchBoostStars
            engine.grantResearchStars(stars)
            return .success("+\(Format.count(stars)) research stars")

        default:
            return .nothingToDo("Unavailable")
        }
    }

    /// Price to skip the coin cost of a specific station's manager, offered on the card.
    static let instantManagerGemCost = 100

    static func hireManagerWithGems(station: Int, engine: GameEngine) -> GemSpendResult {
        let state = engine.state.venues[engine.state.currentVenue].stations[station]
        guard state.isOwned, !state.hasManager else { return .nothingToDo("Already staffed") }
        guard engine.spendGems(instantManagerGemCost) else { return .insufficientGems }
        engine.hireManager(for: station, free: true, premium: true)
        return .success("Manager hired")
    }
}
