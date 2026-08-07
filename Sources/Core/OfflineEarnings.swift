import Foundation

struct OfflineReport: Equatable {
    let elapsed: TimeInterval
    /// Elapsed time after the cap is applied - what the player actually got paid for.
    let credited: TimeInterval
    let coins: Double
    let wasCapped: Bool
    let capHours: Double
}

enum OfflineEarnings {

    /// Only staffed stations earn while the app is closed - that is the whole point of
    /// hiring managers, and it keeps the reward legible.
    static func automatedIncomePerSecond(_ state: GameState) -> Double {
        var total: Double = 0
        for venue in Balance.venues where state.venues[venue.id].unlocked {
            for spec in venue.stations {
                let station = state.venues[venue.id].stations[spec.id]
                guard station.hasManager, station.isOwned else { continue }
                let revenue = Balance.revenuePerCycle(spec: spec, level: station.level)
                total += revenue / Balance.cycleTime(spec: spec, level: station.level)
            }
        }
        // Timed boosts are deliberately excluded: they tick down in real time whether or
        // not the app is open, so paying them out again offline would double-dip.
        return total * Balance.starMultiplier(stars: state.stars) * state.entitlements.profitMultiplier
    }

    /// Returns nil when there is nothing worth showing a welcome-back screen for.
    static func compute(state: GameState, now: Date, minimumSeconds: TimeInterval = 60) -> OfflineReport? {
        let elapsed = now.timeIntervalSince(state.lastSeen)
        guard elapsed >= minimumSeconds else { return nil }

        let capHours = state.entitlements.offlineCapHours
        let cap = capHours * 3600
        let credited = min(elapsed, cap)
        let coins = automatedIncomePerSecond(state) * credited * Balance.offlineEfficiency
        guard coins > 0 else { return nil }

        return OfflineReport(
            elapsed: elapsed,
            credited: credited,
            coins: coins,
            wasCapped: elapsed > cap,
            capHours: capHours
        )
    }
}
