import Foundation

/// Everything layered on top of a station's base curve: chosen perks, the assigned manager,
/// venue-wide manager traits, recipe cards, and research. Resolved once per station so the
/// tick loop stays a couple of multiplications.
struct StationModifiers: Equatable {
    var speed: Double = 1
    var profit: Double = 1
    var doubleServeChance: Double = 0
}

extension GameState {

    func modifiers(venue: Int, station: Int) -> StationModifiers {
        let stationState = venues[venue].stations[station]
        let managers = managerEffects(venue: venue, station: station)
        let effects = researchEffects

        var result = StationModifiers()

        // Perks the player chose at milestone levels.
        result.speed *= Perks.speedMultiplier(chosen: stationState.perks)
        result.profit *= Perks.profitMultiplier(chosen: stationState.perks)
        result.doubleServeChance = Perks.doubleServeChance(chosen: stationState.perks)

        // Staff. Manager speed research only helps stations that actually have someone on them.
        result.speed *= managers.stationSpeed
        if stationState.isStaffed {
            result.speed *= effects.managerSpeedMultiplier
        }
        result.profit *= managers.stationProfit * managers.venueProfit
        // Long service pays: +2% per bond level for the manager actually on this station.
        if let manager = stationManager(venue: venue, station: station) {
            result.profit *= manager.bondProfitMultiplier
        }

        // Assembled crews lift their whole venue - see `Synergies`.
        for synergy in activeSynergies(venue: venue) {
            result.profit *= synergy.venueProfit
        }

        // The venue's Signature Dish (a full 3-star recipe set, distilled) pays x1.5 on
        // the one station the player chose to crown - see `signatureDish`.
        if signatureDish[venue] == station {
            result.profit *= 1.5
        }

        // The Food Truck Rally's twist: one of its stations is today's Daily Special at
        // x3, rotating by (UTC) day - cheap to compute, and a reason to swing by daily.
        if venue == 6, station == Balance.dailySpecialStation(day: Int(now.timeIntervalSince1970 / 86400)) {
            result.profit *= 3
        }

        // The run's Franchise Contract, if any - the whole point is that these touch the
        // same paths everything else does, so a contract run is the same game with the
        // dials moved, not a special mode.
        if let contract {
            result.speed *= contract.speedMultiplier
            result.profit *= contract.profitMultiplier
        }

        // Collection bonuses.
        result.profit *= Recipes.stationMultiplier(recipeCards, venue: venue, station: station)
        result.profit *= Recipes.venueMultiplier(recipeCards, venue: venue)

        return result
    }

    func cycleTime(venue: Int, station: Int) -> TimeInterval {
        let spec = Balance.venue(venue).stations[station]
        let level = venues[venue].stations[station].level
        let base = Balance.cycleTime(spec: spec, level: level)
        return max(Balance.minimumCycle, base / modifiers(venue: venue, station: station).speed)
    }

    /// Payout for one cycle before global multipliers (boosts, stars, VIP, research, combo).
    func baseRevenue(venue: Int, station: Int) -> Double {
        let spec = Balance.venue(venue).stations[station]
        let level = venues[venue].stations[station].level
        return Balance.revenuePerCycle(spec: spec, level: level)
            * modifiers(venue: venue, station: station).profit
    }

    /// Coins per second from staffed stations only - the basis for offline pay, time warps,
    /// and quest coin rewards.
    var automatedRate: Double {
        var total: Double = 0
        for venue in Balance.venues where venues[venue.id].unlocked {
            for spec in venue.stations {
                let station = venues[venue.id].stations[spec.id]
                guard station.isStaffed, station.isOwned else { continue }
                total += baseRevenue(venue: venue.id, station: spec.id)
                    / cycleTime(venue: venue.id, station: spec.id)
            }
        }
        // Keep this list in lockstep with `globalMultiplier` (minus boosts, which tick in
        // real time and are deliberately not paid offline): legacy was missing here for a
        // while, which quietly underpaid every offline report, quest reward, time warp,
        // and errand for anyone past their first Legacy reset.
        return total * Balance.starMultiplier(stars: lifetimeStars)
            * Balance.legacyMultiplier(level: legacy.level)
            * entitlements.profitMultiplier
            * researchEffects.profitMultiplier
            * toolEffects.profitMultiplier
    }

    /// One venue's slice of `automatedRate`, same multipliers - what the Midnight Diner's
    /// full-rate offline twist needs (see OfflineEarnings).
    func automatedRate(venueID: Int) -> Double {
        guard venues.indices.contains(venueID), venues[venueID].unlocked else { return 0 }
        var total: Double = 0
        for spec in Balance.venue(venueID).stations {
            let station = venues[venueID].stations[spec.id]
            guard station.isStaffed, station.isOwned else { continue }
            total += baseRevenue(venue: venueID, station: spec.id)
                / cycleTime(venue: venueID, station: spec.id)
        }
        return total * Balance.starMultiplier(stars: lifetimeStars)
            * Balance.legacyMultiplier(level: legacy.level)
            * entitlements.profitMultiplier
            * researchEffects.profitMultiplier
            * toolEffects.profitMultiplier
    }

    /// Dishes per second from staffed stations only - unlike automatedRate this is a pure
    /// completion count, so it doesn't take the profit multipliers (stars/VIP/research
    /// profit) that don't affect how fast a station actually cycles.
    var automatedServeRate: Double {
        var total: Double = 0
        for venue in Balance.venues where venues[venue.id].unlocked {
            for spec in venue.stations {
                let station = venues[venue.id].stations[spec.id]
                guard station.isStaffed, station.isOwned else { continue }
                total += 1 / cycleTime(venue: venue.id, station: spec.id)
            }
        }
        return total
    }

    /// What a manual tap on a station is worth, including tap-value traits and research.
    func tapMultiplier(venue: Int) -> Double {
        venueManagerEffects(venue: venue).tapValue * researchEffects.tapMultiplier
            * (contract?.tapMultiplier ?? 1) * toolEffects.tapMultiplier
    }

    /// How long the combo window lasts here, extended by traits like Crowd-Reader Cleo.
    func comboWindowBonus(venue: Int) -> TimeInterval {
        venueManagerEffects(venue: venue).comboRetention + toolEffects.comboWindowBonus
    }

    var comboMaxSteps: Int {
        ActivePlay.comboBaseSteps + Int(researchEffects.comboCap)
            + (contract?.comboCapBonus ?? 0) + legacyEffects.comboCapBonus
    }

    var goldenChance: Double {
        min(0.5, ActivePlay.goldenBaseChance * (1 + researchEffects.goldenChance)
            * toolEffects.goldenChanceMultiplier)
    }

    var rushDuration: TimeInterval {
        ActivePlay.rushBaseSeconds + researchEffects.rushSeconds
    }

    // MARK: Staffing

    /// Adds a manager to the roster and puts them straight on a station.
    @discardableResult
    mutating func hire(specID: String, venue: Int, station: Int, premium: Bool = false) -> OwnedManager {
        let manager = OwnedManager.make(specID, premium: premium)
        managers.append(manager)
        assign(managerID: manager.id, venue: venue, station: station)
        return manager
    }

    /// Adds a manager to the roster without putting them to work yet.
    @discardableResult
    mutating func recruit(specID: String, premium: Bool = false) -> OwnedManager {
        let manager = OwnedManager.make(specID, premium: premium)
        managers.append(manager)
        return manager
    }

    /// Assigning someone who is already working elsewhere moves them - a manager can only be
    /// in one place, and silently cloning them would be a duplication bug.
    mutating func assign(managerID: String?, venue: Int, station: Int) {
        if let managerID, let current = assignment(of: managerID) {
            venues[current.venue].stations[current.station].managerID = nil
        }
        venues[venue].stations[station].managerID = managerID
        if managerID != nil {
            venues[venue].stations[station].isRunning = true
            venues[venue].stations[station].everStaffed = true
        }
    }

    /// Offline multiplier from night-shift staff across every open venue.
    var offlineManagerBonus: Double {
        var best = 1.0
        for venue in Balance.venues where venues[venue.id].unlocked {
            best = max(best, venueManagerEffects(venue: venue.id).offlineBonus)
        }
        return best
    }
}
