import Foundation

/// Collectible dish cards. Cards drop when a station levels up, duplicates upgrade the card's
/// star rating, and a complete six-card venue set pays a permanent venue-wide bonus.
enum Recipes {

    static let maxStars = 3
    /// Was 0.08 - at up to 6 roll attempts per buy (see `roll`), a single MAX-buy tap had
    /// close to a 40% chance of a card, so a hyperactively-tapping player (dozens of buys an
    /// hour once managers take over the grind) was maxing out full six-card, 3-star venue
    /// sets within the first hour or two - trivializing the whole collection meta almost
    /// immediately instead of it being a longer-run payoff. Cut 10x.
    static let dropChance = 0.008
    static let starProfitBonus = 0.10   // per star, on that station
    static let setBonus = 0.25          // venue-wide, for a complete set
    static let duplicateGems = 5        // once a card is maxed, extras convert

    static func key(venue: Int, station: Int) -> String { "v\(venue)s\(station)" }

    static func stars(_ cards: [String: Int], venue: Int, station: Int) -> Int {
        min(maxStars, cards[key(venue: venue, station: station)] ?? 0)
    }

    static func owns(_ cards: [String: Int], venue: Int, station: Int) -> Bool {
        stars(cards, venue: venue, station: station) > 0
    }

    /// Extra profit this station earns from its own card.
    static func stationMultiplier(_ cards: [String: Int], venue: Int, station: Int) -> Double {
        1 + Double(stars(cards, venue: venue, station: station)) * starProfitBonus
    }

    static func isSetComplete(_ cards: [String: Int], venue: Int) -> Bool {
        Balance.venue(venue).stations.allSatisfy { owns(cards, venue: venue, station: $0.id) }
    }

    static func venueMultiplier(_ cards: [String: Int], venue: Int) -> Double {
        isSetComplete(cards, venue: venue) ? 1 + setBonus : 1
    }

    static func collected(_ cards: [String: Int], venue: Int) -> Int {
        Balance.venue(venue).stations.filter { owns(cards, venue: venue, station: $0.id) }.count
    }

    static func totalCollected(_ cards: [String: Int]) -> Int {
        Balance.venues.reduce(0) { $0 + collected(cards, venue: $1.id) }
    }

    /// Result of a level-up roll, so the caller can show the right celebration.
    enum Drop: Equatable {
        case none
        case newCard(venue: Int, station: Int)
        case upgraded(venue: Int, station: Int, stars: Int)
        case duplicateGems(Int)
    }

    /// Rolls for a card. `levelsBought` gives bulk purchases proportionally better odds
    /// without letting a MAX buy hand over the whole set at once.
    static func roll(cards: inout [String: Int], venue: Int, station: Int,
                     levelsBought: Int, random: Double) -> Drop {
        let attempts = min(6, max(1, levelsBought))
        let chance = 1 - pow(1 - dropChance, Double(attempts))
        guard random < chance else { return .none }

        let cardKey = key(venue: venue, station: station)
        let current = cards[cardKey] ?? 0

        if current == 0 {
            cards[cardKey] = 1
            return .newCard(venue: venue, station: station)
        }
        if current < maxStars {
            cards[cardKey] = current + 1
            return .upgraded(venue: venue, station: station, stars: current + 1)
        }
        return .duplicateGems(duplicateGems)
    }
}
