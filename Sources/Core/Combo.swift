import Foundation

/// Tuning for the three active-play systems. They exist to give the player a reason to hold
/// the phone once managers have taken over the tapping.
enum ActivePlay {

    // Combo. 10 steps x 0.4/step caps at a clean x5 rather than a stacking-friendly x10 -
    // this multiplies with Coffee Break and Rush Hour on every station's automated income,
    // not just a tapped one, so a lower cap matters more than it looks like it should.
    // The window itself was 1.5s, which reset the whole combo back to zero for anything
    // short of rapid-fire tapping - punishing enough that a normal tap cadence kept dying.
    // 2.5s keeps it an active-play mechanic (still requires genuine engagement, not idle
    // taps minutes apart) without demanding a metronome.
    static let comboWindow: TimeInterval = 2.5
    static let comboBaseSteps = 10
    static let comboPerStep = 0.4

    // Rush Hour
    static let rushBaseSeconds: TimeInterval = 60
    static let rushMultiplier: Double = 5
    static let rushCooldownMinutes: Double = 30
    static let rushGemCost = 40
    static let rushBoostID = "rush-hour"

    // Golden customer
    static let goldenBaseChance = 0.05        // per queue rotation
    static let goldenWindow: TimeInterval = 5
    static let goldenMinSeconds: Double = 30  // of current income
    static let goldenMaxSeconds: Double = 120

    // Customer order - "ORDER UP" on a specific station
    static let orderBaseChance = 0.05          // per queue rotation
    static let orderWindow: TimeInterval = 12
    static let orderBonusMinSeconds: Double = 20  // of current income
    static let orderBonusMaxSeconds: Double = 60

    // Coffee Break - the free boost. This used to be behind a rewarded ad; the game is
    // ad-free, so it is simply given away on a cooldown.
    static let freeBoostMultiplier: Double = 2
    static let freeBoostHours: Double = 0.25       // 15 minutes
    static let freeBoostCooldownMinutes: Double = 30
    static let freeBoostID = "coffee-break"
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
