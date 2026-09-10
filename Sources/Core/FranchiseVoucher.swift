import Foundation

/// A bankable consumable - unlike a kitchen tool (passive forever the moment it's found) or a
/// boost (applies itself the moment it's granted), this sits in inventory until the player
/// deliberately spends it. Two ways in: one guaranteed per Franchise (`GameEngine.prestige`)
/// and a rare mid-play drop (`ActivePlay.voucherDropBaseChance`, rolled in
/// `GameEngine.advance(by:)`) - both funnel through `GameEngine.addFranchiseVoucher` so the
/// cap below is enforced in exactly one place. Using one rolls ONE effect from the table
/// below, active for `effectDurationHours` of active play - see each effect's own doc comment
/// for why none of them touch offline/idle payout.
enum FranchiseVoucher {
    static let id = "franchiseVoucher"

    /// However many a player can bank at once. Rush Hour (below) alone rolls the same flat
    /// x5 `ActivePlay.rushMultiplier` the game already paces with a 30-minute cooldown and a
    /// chain bonus that resets the moment a return lapses - a banked voucher has no cooldown
    /// on USE, only on acquisition, so an unbounded stockpile would let a player chain x5
    /// hours back to back for as long as the bank lasted, undoing that pacing through a side
    /// door. 3 echoes `ActivePlay.rushChainMax` (also 3) - the same ceiling the game already
    /// puts on how much consecutive x5 stacking it considers healthy, applied here to the
    /// same effect arriving by a different door.
    static let inventoryCap = 3

    static let effectDurationHours: Double = 1

    static let rushHourMultiplier: Double = 5
    static let rushHourBoostID = "franchise-voucher-rush"

    /// Same order of magnitude as the Debug menu's own Gold Spatula luck toggle
    /// (`GameEngine.goldSpatulaLuckBoostEnabled`, +0.05) - a real nudge for the hour, never a
    /// guarantee.
    static let luckyHourLegendaryChance: Double = 0.05

    /// Deliberately NOT equal to `rushHourMultiplier` - a fully-staffed board (the common
    /// end-game shape) already makes "automated only" close to "everywhere," so matching Rush
    /// Hour's x5 exactly would make this a strict upgrade wearing a different name. A notch
    /// under it keeps the two effects a real tradeoff rather than a reskin.
    static let allHandsMultiplier: Double = 4

    enum Effect: CaseIterable, Equatable {
        case rushHour, luckyHour, allHandsOnDeck

        /// Weighted like `Tools.all`'s rarity tiers: Rush Hour is the plain, common result -
        /// a flat multiplier, no interaction with anything else - the other two are rarer
        /// since each is a bigger structural nudge for the hour, not just a bigger number on
        /// the same dial.
        var weight: Double {
            switch self {
            case .rushHour: return 60
            case .luckyHour: return 20
            case .allHandsOnDeck: return 20
            }
        }

        var label: String {
            switch self {
            case .rushHour: return "Rush Hour Voucher"
            case .luckyHour: return "Lucky Hour"
            case .allHandsOnDeck: return "All Hands on Deck"
            }
        }

        var detail: String {
            switch self {
            case .rushHour:
                return "×\(Format.trim(FranchiseVoucher.rushHourMultiplier)) profit, everywhere, for the hour."
            case .luckyHour:
                return "Every kitchen tool roll for the hour gets a boosted shot at Legendary."
            case .allHandsOnDeck:
                return "Your staffed stations earn ×\(Format.trim(FranchiseVoucher.allHandsMultiplier)) for the hour - tapping still pays its usual rate."
            }
        }

        var symbol: String {
            switch self {
            case .rushHour: return "bolt.fill"
            case .luckyHour: return "clover.fill"
            case .allHandsOnDeck: return "person.3.fill"
            }
        }
    }

    /// Weighted walk identical in shape to `Tools.roll` - `random` is a single pre-rolled
    /// value rather than live RNG, so tests can pin the outcome.
    static func rollEffect(random: Double) -> Effect {
        let all = Effect.allCases
        let total = all.reduce(0) { $0 + $1.weight }
        var cursor = random * total
        for effect in all {
            cursor -= effect.weight
            if cursor <= 0 { return effect }
        }
        return all.last!
    }
}
