import Foundation

/// The single "what should I be doing right now?" answer, shown as a persistent chip on the
/// HUD. Born from a real playtest: a first-time player (not an idle-game player) got
/// through the tutorial fine and still had no idea what the *point* was - the
/// earn -> automate -> expand -> Franchise -> research -> Legacy arc is invisible until you
/// stumble into it. The coach cards teach controls; this teaches direction.
///
/// Pure derivation from state - no persistence, no bookkeeping to migrate. The ladder is
/// ordered; the first unmet rung is the goal. Rungs deliberately alternate between board
/// goals and meta goals so the chip keeps changing early, when attention is most fragile.
struct Goal: Equatable {
    let id: String
    /// Imperative, chip-sized ("Hire your first manager").
    let title: String
    /// One sentence of why it matters, revealed when the chip is tapped.
    let detail: String
}

enum GoalDirector {

    /// The first unmet rung, or nil once the ladder is exhausted (Legacy 3+ veterans need
    /// no chip - the Roadmap takes over as the long-range view by then).
    static func currentGoal(for state: GameState) -> Goal? {
        let staffed = state.assignedManagerCount
        let bestLevel = Quests.highestStationLevel(state)
        let venuesOpen = state.venues.filter(\.unlocked).count

        if staffed == 0 {
            return Goal(id: "first-manager", title: "Hire your first manager",
                        detail: "A staffed station runs itself - even while the app is closed. Everything starts here.")
        }
        if bestLevel < 25 {
            return Goal(id: "level-25", title: "Take a station to Lv 25",
                        detail: "Milestone levels pay huge speed and profit jumps - and Lv 25 unlocks your first perk choice.")
        }
        if venuesOpen < 2 {
            return Goal(id: "venue-2", title: "Open your second venue",
                        detail: "A new venue earns far more than more levels in the old one. The Venues tab shows the price.")
        }
        if staffed < 5 {
            return Goal(id: "staff-5", title: "Staff five stations",
                        detail: "Every staffed station keeps earning while you're away - this is how the empire runs without you.")
        }
        if state.prestigeCount == 0 {
            let fraction = min(1, state.lifetimeEarnings / Balance.minimumLifetimeForPrestige)
            return Goal(id: "first-franchise", title: "Reach your first Franchise",
                        detail: "The real game: reset the board for Stars - a permanent profit bonus that carries into every future run. You're \(Int(fraction * 100))% of the way there.")
        }
        if state.research.isEmpty {
            return Goal(id: "first-research", title: "Buy your first research",
                        detail: "Spend the Stars you just earned - research is permanent and survives every reset. Tap the star pill, then Research.")
        }
        if venuesOpen < 5 {
            return Goal(id: "all-venues", title: "Open all five venues",
                        detail: "The full food court. Each venue multiplies what a run can earn - and what your next Franchise awards.")
        }
        if state.prestigeCount < Balance.legacyUnlockPrestigeCount {
            return Goal(id: "franchise-5", title: "Franchise \(Balance.legacyUnlockPrestigeCount) times",
                        detail: "You're \(state.prestigeCount) of \(Balance.legacyUnlockPrestigeCount). Costs creep up on a stale board - resetting every few days beats waiting. Five franchises unlock Legacy.")
        }
        if state.legacy.level == 0 {
            return Goal(id: "first-legacy", title: "Consider your first Legacy",
                        detail: "Trade your stars and research for a permanent +20% multiplier and start the climb again, bigger. Optional - the Franchise tab has the details.")
        }
        if state.legacy.level < 3 {
            return Goal(id: "legacy-3", title: "Reach Legacy \(state.legacy.level + 1)",
                        detail: "Each Legacy stacks another permanent +20%. The Roadmap (Franchise → Map) tracks the whole journey.")
        }
        return nil
    }
}
