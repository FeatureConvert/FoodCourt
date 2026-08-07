import Foundation

/// Timed multipliers stack multiplicatively. Adding a boost that is already running
/// extends it rather than replacing it, so a player who buys two hours never loses time.
enum Boosts {

    static func add(_ boost: BoostState, to state: inout GameState) {
        let now = state.now
        prune(&state)

        if let index = state.boosts.firstIndex(where: { $0.id == boost.id }) {
            let existing = state.boosts[index]
            let remaining = existing.remaining(at: now)
            let added = boost.remaining(at: now)
            state.boosts[index].expiry = now.addingTimeInterval(remaining + added)
            state.boosts[index].multiplier = boost.multiplier
            state.boosts[index].label = boost.label
        } else {
            state.boosts.append(boost)
        }
    }

    static func prune(_ state: inout GameState) {
        let now = state.now
        state.boosts.removeAll { !$0.isActive(at: now) }
    }

    static func make(id: String, label: String, multiplier: Double, hours: Double, from now: Date) -> BoostState {
        BoostState(id: id, label: label, multiplier: multiplier, expiry: now.addingTimeInterval(hours * 3600))
    }
}
