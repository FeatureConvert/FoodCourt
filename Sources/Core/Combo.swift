import Foundation

/// Tuning for the three active-play systems. They exist to give the player a reason to hold
/// the phone once managers have taken over the tapping.
enum ActivePlay {

    // Combo. This multiplies with Coffee Break, Rush Hour, and Happy Hour on every
    // station's automated income, not just a tapped one - a live report showed a
    // hyperactive fresh install banking the Sushi Bar in 8 real minutes, and stacking
    // this at its old flat x5 with the free Coffee Break boost and Happy Hour hit up to
    // ~15x automated income, dwarfing the pacing sim's assumptions. That history is why
    // this is tiers now rather than one smooth ramp: every tier past the first costs the
    // same 25 taps for the same +0.5x, so the ceiling is a real, sustained-engagement
    // achievement rather than something a lucky burst reaches once and then coasts on.
    //
    // Tier 0 is deliberately short - 5 taps to x1.5 - so a casual player still feels an
    // early, easy reward. Every tier after that is priced the same (25 taps) for the same
    // reward (+0.5x), which is what makes "another 25 taps" a legible rule rather than a
    // curve a player has to feel out.
    //
    // Four tiers land the ceiling at x3, not the x5 an earlier pass shipped: a
    // maximally-hyperactive fresh install (every owned station tapped on every tick, never
    // once dropping a tier) clears all 180 cumulative taps to x5 in about ten seconds and
    // then sustains it for the rest of the session, which regressed
    // `EarlyGamePacingTests.testHyperactiveFreshInstallCannotRushTheSushiBar` (the direct
    // regression test for the x15-stack incident above) - it banked the Sushi Bar at ~15
    // minutes against the 20-minute floor. x3 stacked with Coffee Break and Happy Hour
    // tops out at x9, comfortably clear of that floor again; the escalating-tap-cost,
    // shrinking-window shape below is otherwise unchanged from the original design.
    //
    // The window - how long you can go between taps before the WHOLE combo resets to
    // zero, not just the current tier - shrinks every tier, from a forgiving 10s at tier 0
    // down to 7s at tier 3. A ladder that got easier to sustain the higher it climbed would
    // make x3 the new normal instead of a ceiling; shrinking the window is what keeps each
    // higher tier feeling like it costs more attention, not just more history of tapping.
    //
    // `comboBonusTaps` (StationMath.swift) adds bonus taps toward this same ladder from
    // Research's Kitchen Rhythm, Legacy's Crowd Favorite, and an active Showtime Franchise
    // Contract - each an earned late-game investment, so a min-maxed player climbing the
    // ladder faster is intentional depth, not a fresh-install exploit.
    struct ComboTier {
        let taps: Int
        let multiplier: Double
        let window: TimeInterval
    }

    static let comboTiers: [ComboTier] = [
        ComboTier(taps: 5, multiplier: 1.5, window: 10.0),
        ComboTier(taps: 25, multiplier: 2.0, window: 9.0),
        ComboTier(taps: 25, multiplier: 2.5, window: 8.0),
        ComboTier(taps: 25, multiplier: 3.0, window: 7.0),
    ]

    /// Running total of taps needed to CLEAR each tier (index-aligned with `comboTiers`),
    /// e.g. `[5, 30, 55, ...]` - tier 1 clears at 30 total taps, not 25, since tier 0's 5
    /// still count.
    static var comboCumulativeTaps: [Int] {
        var running = 0
        return comboTiers.map { tier in running += tier.taps; return running }
    }

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

    /// Which tier's bar is currently filling, and exactly how many of that tier's taps are
    /// done - e.g. `(index: 2, tapsDone: 6, tapsRequired: 25)`. Once every tier is cleared,
    /// reports the last tier full: there's nothing further to fill toward, x5 is the ceiling.
    func activeTier(bonusTaps: Int) -> (index: Int, tapsDone: Int, tapsRequired: Int) {
        let effective = count + bonusTaps
        var previousThreshold = 0
        for (index, threshold) in ActivePlay.comboCumulativeTaps.enumerated() {
            if effective < threshold {
                return (index, effective - previousThreshold, ActivePlay.comboTiers[index].taps)
            }
            previousThreshold = threshold
        }
        let last = ActivePlay.comboTiers.count - 1
        return (last, ActivePlay.comboTiers[last].taps, ActivePlay.comboTiers[last].taps)
    }

    /// The last tier fully CLEARED, as an index into `comboTiers` - -1 if none yet (1x).
    private func achievedTierIndex(bonusTaps: Int) -> Int {
        let effective = count + bonusTaps
        var achieved = -1
        for (index, threshold) in ActivePlay.comboCumulativeTaps.enumerated() where effective >= threshold {
            achieved = index
        }
        return achieved
    }

    /// The multiplier actually in effect - the last tier whose bar has been fully CLEARED,
    /// not the one still filling. Stays at 1x until tier 0's bar completes.
    func multiplier(bonusTaps: Int) -> Double {
        guard count > 0 else { return 1 }
        let achieved = achievedTierIndex(bonusTaps: bonusTaps)
        return achieved >= 0 ? ActivePlay.comboTiers[achieved].multiplier : 1
    }

    /// Registers a tap. `bonusTaps` is the same late-game bonus `activeTier`/`multiplier`
    /// take, needed here too so the window matches whichever tier this tap just landed in -
    /// a bonus-boosted player who just crossed into a hotter tier should immediately get
    /// that tier's shorter window, not the previous one's. `windowBonus` is a separate flat
    /// add-on from manager traits like Crowd-Reader Cleo.
    mutating func register(at now: Date, bonusTaps: Int = 0, windowBonus: TimeInterval = 0) {
        // Catches up a depletion step that was due but hadn't run yet (prune normally runs
        // every engine tick, well before a tap could land after expiry - this just keeps
        // register correct even if that ordering ever changes) rather than silently
        // honoring a tap against an already-stale window.
        if count > 0, expiresAt <= now { _ = prune(at: now, bonusTaps: bonusTaps) }
        count += 1
        let tierIndex = max(0, achievedTierIndex(bonusTaps: bonusTaps))
        expiresAt = now.addingTimeInterval(ActivePlay.comboTiers[tierIndex].window + windowBonus)
    }

    /// Drops the combo one tier at a time once its window lapses, rather than to zero in
    /// one shot - a x5 combo lost to one slow moment should cost a tier, not the whole
    /// climb. Each step reschedules against the tier it lands on, so a still-idle player
    /// keeps stepping down (faster near the top, since higher tiers carry shorter windows)
    /// until either a tap saves it or it bottoms out at nothing. Returns true when a step
    /// actually happened.
    @discardableResult
    mutating func prune(at now: Date, bonusTaps: Int = 0) -> Bool {
        guard count > 0, expiresAt <= now else { return false }
        let droppedTo = achievedTierIndex(bonusTaps: bonusTaps) - 1
        guard droppedTo >= 0 else {
            count = 0
            expiresAt = .distantPast
            return true
        }
        count = max(0, ActivePlay.comboCumulativeTaps[droppedTo] - bonusTaps)
        expiresAt = now.addingTimeInterval(ActivePlay.comboTiers[droppedTo].window)
        return true
    }

    mutating func reset() {
        count = 0
        expiresAt = .distantPast
    }
}
