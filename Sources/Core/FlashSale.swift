import Foundation

/// A time-limited bump to how many gems one specific pack grants, at its normal real-money
/// price. Apple sets IAP prices in App Store Connect - the app can't discount those on its
/// own - so a "sale" here means the price stays exactly what it always was and the grant is
/// what varies for the window. `StoreService.grant` checks this at purchase time.
struct FlashSale: Codable, Equatable {
    let packID: String
    let bonusGems: Int
    let startedAt: Date
    let expiresAt: Date

    func isActive(at date: Date) -> Bool { date < expiresAt }
}

enum FlashSaleKit {
    /// Same anchor pack the rest of the store is already tuned around (see ShopCatalog's
    /// own "the $5 anchor" comment) - a flash sale works best on a low-commitment impulse
    /// buy, not a whale-tier pack, and reusing the pack the economy already expects players
    /// to reach for keeps the messaging ("this is the smart buy") consistent rather than
    /// diluted across a rotating cast.
    static let packID = ShopCatalog.prefix + "gems.pouch"
    static let baseGems = 550
    /// +40% - more generous than any permanent tier badge (Chest's +20%, Vault's +35%) so
    /// the sale reads as a genuine step up, not just another shelf price.
    static let bonusFraction = 0.4
    static let duration: TimeInterval = 3 * 3600
    /// Randomized, not fixed, so sales land unpredictably rather than on a clockable daily
    /// schedule - "random pops", while still guaranteeing one roughly once a day on average.
    static let cooldownRange: ClosedRange<TimeInterval> = (18 * 3600)...(30 * 3600)

    static func roll(now: Date) -> FlashSale {
        let bonus = Int((Double(baseGems) * (1 + bonusFraction)).rounded())
        return FlashSale(packID: packID, bonusGems: bonus,
                         startedAt: now, expiresAt: now.addingTimeInterval(duration))
    }

    /// True system randomness, not the deterministic SeededRandom used for stable art
    /// re-renders - sale timing needs to be genuinely unpredictable across real sessions.
    static func randomCooldown() -> TimeInterval { .random(in: cooldownRange) }
}
