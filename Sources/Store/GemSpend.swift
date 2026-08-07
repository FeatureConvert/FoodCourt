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
        GemOffer(id: "manager", title: "Instant Manager",
                 subtitle: "Staff your cheapest open station", cost: 100, symbol: "person.fill.badge.plus"),
        GemOffer(id: "timewarp", title: "Time Warp",
                 subtitle: "Collect 4 hours of income now", cost: 150, symbol: "clock.arrow.circlepath"),
        GemOffer(id: "instant", title: "Serve Everyone",
                 subtitle: "Finish every station's cycle instantly", cost: 20, symbol: "hand.tap.fill"),
    ]
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

        case "manager":
            guard let target = cheapestUnmanagedStation(engine: engine) else {
                return .nothingToDo("Every open station is already staffed")
            }
            guard engine.spendGems(offer.cost) else { return .insufficientGems }
            engine.hireManager(for: target, free: true)
            let name = Balance.venue(engine.state.currentVenue).stations[target].name
            return .success("\(name) is now staffed")

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

        default:
            return .nothingToDo("Unavailable")
        }
    }

    /// The manager offer targets the cheapest station the player has open but not staffed,
    /// which is almost always the one they want and saves them a picker.
    static func cheapestUnmanagedStation(engine: GameEngine) -> Int? {
        let venue = Balance.venue(engine.state.currentVenue)
        return venue.stations
            .filter { spec in
                let station = engine.state.venues[venue.id].stations[spec.id]
                return station.isOwned && !station.hasManager
            }
            .min { Balance.managerCost(spec: $0) < Balance.managerCost(spec: $1) }?
            .id
    }

    /// Price to skip the coin cost of a specific station's manager, offered on the card.
    static let instantManagerGemCost = 100

    static func hireManagerWithGems(station: Int, engine: GameEngine) -> GemSpendResult {
        let state = engine.state.venues[engine.state.currentVenue].stations[station]
        guard state.isOwned, !state.hasManager else { return .nothingToDo("Already staffed") }
        guard engine.spendGems(instantManagerGemCost) else { return .insufficientGems }
        engine.hireManager(for: station, free: true)
        return .success("Manager hired")
    }
}
