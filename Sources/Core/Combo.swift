import Foundation

/// Tuning for the three active-play systems. They exist to give the player a reason to hold
/// the phone once managers have taken over the tapping.
enum ActivePlay {

    // Combo. This multiplies with Coffee Break, Rush Hour, and Happy Hour on every
    // station's automated income, not just a tapped one - a live report showed a
    // hyperactive fresh install banking the Sushi Bar in 8 real minutes, and stacking
    // this at its old x5 (10 steps x 0.4/step) with the free Coffee Break boost and Happy
    // Hour hit up to ~15x automated income, dwarfing the pacing sim's assumptions. 10
    // steps x 0.1/step caps at a clean x2 instead - still a genuine reward for active
    // tapping, without letting the combo alone dominate the early economy.
    // The window itself was 1.5s, then 2.5s, both of which reset the whole combo back to
    // zero for anything short of rapid-fire tapping - punishing enough that a normal tap
    // cadence across multiple stations (not just one under a thumb) kept dying. 5s keeps it
    // an active-play mechanic (still requires genuine engagement, not idle taps minutes
    // apart) without demanding a metronome.
    static let comboWindow: TimeInterval = 5.0
    static let comboBaseSteps = 10
    static let comboPerStep = 0.1

    // Rush Hour
    static let rushBaseSeconds: TimeInterval = 60
    static let rushMultiplier: Double = 5
    static let rushCooldownMinutes: Double = 30
    static let rushGemCost = 40
    static let rushBoostID = "rush-hour"

    // Golden customer. The per-rotation chance was tuned when a rotation meant a leisurely
    // cycle; a leveled station rotates the queue every 0.35s (the UI throttle), which made
    // 5% mean "a VIP every seven seconds." A hyperactive fresh install was measured taking
    // HALF its lifetime income from goldens and banking the 800K Sushi Bar inside ten
    // minutes. The cooldown makes rarity a design constant instead of a side effect of
    // cycle speed, and the payout window shrinks to match the new cadence - tips are a
    // treat on top of the board, not a second economy.
    static let goldenBaseChance = 0.05        // per queue rotation, once off cooldown
    static let goldenCooldown: TimeInterval = 90
    static let goldenWindow: TimeInterval = 5
    static let goldenMinSeconds: Double = 15  // of current income
    static let goldenMaxSeconds: Double = 45

    // Customer order - "ORDER UP" on a specific station. Same cooldown treatment as the
    // golden customer, slightly more frequent and smaller.
    static let orderBaseChance = 0.05          // per queue rotation, once off cooldown
    static let orderCooldown: TimeInterval = 60
    static let orderWindow: TimeInterval = 12
    static let orderBonusMinSeconds: Double = 10  // of current income
    static let orderBonusMaxSeconds: Double = 30

    /// Tips and order bonuses are "N seconds of income", but a fresh board earns ~1/s and
    /// the old flat floor of 50/s was a mid-game number - on day one it quietly paid 25-50x
    /// the board's real rate and bankrolled the whole early game. Scaling the floor to the
    /// venue's opening station keeps a first-minute tip feeling generous (a few station
    /// levels' worth) at every venue depth without warping anything.
    static func tipFloorRate(venue: Int) -> Double {
        let opener = Balance.venue(venue).stations[0]
        return opener.baseRevenue / opener.baseCycle * 3
    }

    // Coffee Break - the free boost. This used to be behind a rewarded ad; the game is
    // ad-free, so it is simply given away on a cooldown.
    static let freeBoostMultiplier: Double = 2
    static let freeBoostHours: Double = 0.25       // 15 minutes
    static let freeBoostCooldownMinutes: Double = 30
    static let freeBoostID = "coffee-break"

    // Rush chains - starting a Rush within this window of the cooldown ending keeps the
    // chain alive; each tier past the first adds +25% to the Rush multiplier, capped at 3.
    static let rushChainWindowSeconds: TimeInterval = 3600
    static let rushChainMax = 3

    // VIP critic - the rare golden-customer jackpot.
    static let criticChance = 0.05
    static let criticMultiplier: Double = 10

    // Happy Hour - a fixed daily 6-8pm local window with boosted tips and doubled golden
    // odds. Computed from the clock, never scheduled or persisted: a time-of-day habit
    // anchor, deliberately during the after-work stretch when a session is most plausible.
    static let happyHourStartHour = 18
    static let happyHourEndHour = 20
    static let happyHourMultiplier: Double = 1.5
}

/// Transient combo state. Deliberately not persisted - a combo you left an hour ago should
/// not still be running when you come back.
struct ComboTracker: Equatable {
    private(set) var count: Int = 0
    private(set) var expiresAt: Date = .distantPast

    var isActive: Bool { count > 0 }

    func isLive(at now: Date) -> Bool { count > 0 && expiresAt > now }

    func remaining(at now: Date) -> TimeInterval { max(0, expiresAt.timeIntervalSince(now)) }

    /// Progress toward the cap, for the meter fill.
    func fraction(maxSteps: Int) -> Double {
        guard maxSteps > 0 else { return 0 }
        return min(1, Double(count) / Double(maxSteps))
    }

    func multiplier(maxSteps: Int) -> Double {
        guard count > 0 else { return 1 }
        return 1 + Double(min(count, maxSteps)) * ActivePlay.comboPerStep
    }

    /// Registers a tap. `windowBonus` comes from manager traits like Crowd-Reader Cleo.
    mutating func register(at now: Date, windowBonus: TimeInterval = 0) {
        if expiresAt <= now { count = 0 }
        count += 1
        expiresAt = now.addingTimeInterval(ActivePlay.comboWindow + windowBonus)
    }

    /// Drops the combo once the window lapses. Returns true when it actually expired.
    @discardableResult
    mutating func prune(at now: Date) -> Bool {
        guard count > 0, expiresAt <= now else { return false }
        count = 0
        expiresAt = .distantPast
        return true
    }

    mutating func reset() {
        count = 0
        expiresAt = .distantPast
    }
}
