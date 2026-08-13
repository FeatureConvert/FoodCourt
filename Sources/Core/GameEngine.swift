import Foundation
import Combine

enum BuyQuantity: String, CaseIterable, Identifiable {
    case x1, x10, x100, next, max
    var id: String { rawValue }
    var label: String {
        switch self {
        case .x1: return "×1"
        case .x10: return "×10"
        case .x100: return "×100"
        case .next: return "NEXT"
        case .max: return "MAX"
        }
    }
    /// nil for both .max and .next: neither is a flat count. .max depends on coins on hand;
    /// .next depends on a station's current level (how far to its next milestone), which
    /// differs per station - GameEngine.quantity(for:in:) computes it there instead.
    var fixedAmount: Int? {
        switch self {
        case .x1: return 1
        case .x10: return 10
        case .x100: return 100
        case .next: return nil
        case .max: return nil
        }
    }
}

/// One completed cycle. The UI turns these into coin bursts and served customers.
struct ServeEvent: Identifiable, Equatable {
    let id = UUID()
    let station: Int
    let amount: Double
    let count: Int
}

/// A golden customer waiting to be tapped.
struct GoldenCustomer: Identifiable, Equatable {
    let id = UUID()
    let seed: Int
    let expiresAt: Date
    /// One in twenty golden customers is a VIP critic: x10 the usual payout and its own
    /// fanfare. A rare jackpot on an existing spawn is the cheapest thrill in the game.
    var isCritic: Bool = false
}

/// Everything the just-finished franchise run was, captured at the moment of reset for the
/// end-of-run recap - the board wipes these numbers the same instant they become worth
/// celebrating, so they have to be copied out first.
struct RunRecap: Equatable {
    let duration: TimeInterval
    let earned: Double
    let served: Int
    let starsAwarded: Int
    let prestigeNumber: Int
}

/// A specific station asking for a serve within a short window, for a coin bonus. Mirrors
/// GoldenCustomer's shape exactly - transient, engine-only, never persisted - just retargeted
/// at "the next completed cycle on this station" instead of a floating tap.
struct StationOrder: Equatable {
    let venue: Int
    let station: Int
    let expiresAt: Date
}

@MainActor
final class GameEngine: ObservableObject {

    @Published private(set) var state: GameState
    @Published private(set) var lastServe: [Int: ServeEvent] = [:]
    @Published private(set) var servedCustomers: Int = 0
    /// Backed directly by `UserDefaults`, same as `SoundService`'s reason for doing the same
    /// thing rather than `@AppStorage` (that wrapper only works inside a View) - a device
    /// preference, not game state, so it doesn't belong in the save file. Used to just default
    /// back to .x1 on every launch, which was a real annoyance for anyone who always buys at
    /// x100 or Max. Read/write both gated on `EphemeralPersistence` in `init`/`didSet` below -
    /// the test host and the app under test share one real `UserDefaults.standard`, so without
    /// that gate a test setting `.max` would leak into every later test in the same run (and
    /// into a real device's saved preference during local development).
    @Published var buyQuantity: BuyQuantity = .x1 {
        didSet {
            guard !(persistence is EphemeralPersistence) else { return }
            UserDefaults.standard.set(buyQuantity.rawValue, forKey: "buyQuantity")
        }
    }

    @Published var pendingOfflineReport: OfflineReport?

    // Active play
    @Published private(set) var combo = ComboTracker()
    @Published private(set) var golden: GoldenCustomer?
    @Published private(set) var activeOrder: StationOrder?

    /// Transient banners the UI reacts to.
    @Published var pendingPerkStation: Int?
    @Published var lastRecipeDrop: Recipes.Drop?
    @Published var pendingLeagueOutcome: LeagueOutcome?
    @Published var toast: String?
    /// A lifetime-earnings landmark (1M, 1B, 1T...) crossed this session, waiting on its
    /// celebration. Set at most once per landmark per save - see `registerLandmarks`.
    @Published var pendingLandmark: Double?
    /// A kitchen tool that just dropped (newly found, not a duplicate), waiting on its
    /// celebration - the Gold Spatula gets the biggest moment in the game.
    @Published var pendingToolDrop: ToolItem?
    /// Set by `prestige()` for the end-of-run recap the UI shows after the reset - the
    /// numbers have to be captured BEFORE the board wipes them.
    @Published var lastRunRecap: RunRecap?
    /// Payouts waiting to be shown, and when each station last showed one. A fast station
    /// completes ten-plus cycles a second; spawning a burst per cycle restarts the animation
    /// before it can play, so they are pooled and shown as one larger number.
    private var pendingBursts: [Int: (amount: Double, count: Int)] = [:]
    private var lastBurstAt: [Int: CFTimeInterval] = [:]
    private static let burstMinimumInterval: CFTimeInterval = 0.25

    /// `state.modifiers(venue:station:)` walks every manager in the venue plus the research
    /// and tools dictionaries, and `advance(by:)` already computes it once per owned station
    /// on every tick to run the actual game math. Station-row UI wants the same numbers just
    /// to display them, so it reads this cache (refreshed every tick, ~50ms) instead of
    /// redoing that walk again on every render. `cachedModifiers` falls back to a direct
    /// (correct, just uncached) computation for anything not yet in here - a fresh
    /// preview/test engine that never ticks, or a station advance() hasn't reached yet -
    /// so a cache miss can never show a wrong number, only an uncached one.
    private struct StationKey: Hashable { let venue: Int; let station: Int }
    private var modifiersCache: [StationKey: StationModifiers] = [:]

    func cachedModifiers(venue: Int, station: Int) -> StationModifiers {
        modifiersCache[StationKey(venue: venue, station: station)]
            ?? state.modifiers(venue: venue, station: station)
    }

    func cachedCycleTime(venue: Int, station: Int) -> TimeInterval {
        let spec = Balance.venue(venue).stations[station]
        let level = state.venues[venue].stations[station].level
        let base = Balance.cycleTime(spec: spec, level: level)
        return max(Balance.minimumCycle, base / cachedModifiers(venue: venue, station: station).speed)
    }

    func cachedBaseRevenue(venue: Int, station: Int) -> Double {
        let spec = Balance.venue(venue).stations[station]
        let level = state.venues[venue].stations[station].level
        return Balance.revenuePerCycle(spec: spec, level: level)
            * cachedModifiers(venue: venue, station: station).profit
    }

    private let persistence: GamePersisting
    /// Every chance-driven system draws from here. Production uses the system generator;
    /// tests pin it to a `SplitMix64` seed so the pacing sims measure tuning rather than
    /// luck - see GameRandom.swift.
    var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
    private var tickTimer: Timer?
    private var autosaveTimer: Timer?
    private var lastTickTime: CFTimeInterval = CACurrentMediaTimeCompat()

    // MARK: Lifecycle

    init(state: GameState? = nil,
         startTimers: Bool = true,
         persistence: GamePersisting = DiskPersistence()) {
        self.persistence = persistence
        self.state = state ?? persistence.load()
        self.state.reconcileWithCatalog()
        Boosts.prune(&self.state)
        if !(persistence is EphemeralPersistence),
           let raw = UserDefaults.standard.string(forKey: "buyQuantity"),
           let saved = BuyQuantity(rawValue: raw) {
            buyQuantity = saved
        }
        bootstrapSystems()
        if startTimers { start() }
    }

    /// Fills in anything a fresh or migrated save is missing: quest slots and a seeded league.
    private func bootstrapSystems() {
        Quests.refill(state: &state, incomePerSecond: state.automatedRate)
        if state.league.rivals.isEmpty {
            state.league = League.newWeek(tier: state.league.tier,
                                          now: state.now,
                                          seasonsPlayed: state.league.seasonsPlayed,
                                          nemesisSeed: state.nemesisSeed)
        }
        Festival.rolloverIfNeeded(&state.festival, now: state.now)
        rollWeeklyQuestIfNeeded()
        rollCateringIfNeeded()
    }

    func start() {
        guard tickTimer == nil else { return }
        lastTickTime = CACurrentMediaTimeCompat()

        let tick = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick

        let save = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.save() }
        }
        RunLoop.main.add(save, forMode: .common)
        autosaveTimer = save
    }

    func stop() {
        tickTimer?.invalidate(); tickTimer = nil
        autosaveTimer?.invalidate(); autosaveTimer = nil
    }

    func save() {
        accrueBondTime()
        state.lastSeen = state.now
        persistence.save(state)
    }

    /// Adds elapsed time to every ASSIGNED manager's bond clock. Runs on the autosave
    /// cadence (every ~5s live, plus background/foreground), so bench time and errand time
    /// correctly never count - only actual service on a station builds the bond.
    private func accrueBondTime() {
        let now = state.now
        let deltaDays = now.timeIntervalSince(state.lastBondAccrualAt) / 86400
        state.lastBondAccrualAt = now
        guard deltaDays > 0, deltaDays < 365 else { return } // clock-skew guard
        let assigned = state.assignedManagerIDs
        guard !assigned.isEmpty else { return }
        for index in state.managers.indices where assigned.contains(state.managers[index].id) {
            state.managers[index].bondDays += deltaDays
        }
    }

    // MARK: Foreground / background

    func handleForeground() {
        Boosts.prune(&state)
        if let report = OfflineEarnings.compute(state: state, now: state.now) {
            state.coins += report.coins
            recordEarnings(report.coins)
            pendingOfflineReport = report
            // Win-back: three-plus days away earns a free Grand Reopening rather than a
            // guilt trip - a returning lapsed player should land on their best day.
            if report.elapsed >= 3 * 24 * 3600 {
                addBoost(id: "grand-reopening", label: "Grand Reopening ×2",
                         multiplier: 2, hours: 24)
                toast = "Welcome back! Grand Reopening: ×2 profit for 24h, on the house."
            }
        }
        Festival.rolloverIfNeeded(&state.festival, now: state.now)
        League.advanceRivals(&state.league, to: state.now, playerRate: state.automatedRate)
        settleLeagueIfFinished()
        rollWeeklyQuestIfNeeded()
        rollCateringIfNeeded()
        state.lastSeen = state.now
        lastTickTime = CACurrentMediaTimeCompat()
    }

    func handleBackground() {
        save()
        // KVS wants infrequent writes, so the cloud push happens on the way out rather than
        // on every five-second autosave.
        cloud?.push(state)
    }

    /// Set by the app once both objects exist.
    private weak var cloud: CloudSaveService?
    func attachCloud(_ service: CloudSaveService) { cloud = service }

    /// Replaces local progress with a save from another device.
    func adoptCloudSave(_ incoming: GameState) {
        stop()
        state = incoming
        state.reconcileWithCatalog()
        Boosts.prune(&state)
        lastServe.removeAll()
        pendingBursts.removeAll()
        lastBurstAt.removeAll()
        combo.reset()
        golden = nil
        activeOrder = nil
        bootstrapSystems()
        save()
        start()
    }

    @discardableResult
    func pushToCloud() -> Bool { cloud?.push(state) ?? false }

    // MARK: Tick

    private func step() {
        let now = CACurrentMediaTimeCompat()
        var delta = now - lastTickTime
        lastTickTime = now
        delta = min(max(delta, 0), 1.0)
        guard delta > 0 else { return }
        advance(by: delta)
    }

    /// Wall clock of the last `advance`. Deliberately not `@Published`: views read it inside
    /// a `TimelineView` to interpolate between ticks, so a progress ring animates at the
    /// display's refresh rate instead of stepping at the engine's 20Hz.
    private(set) var lastAdvanceAt = Date()

    /// Exposed for tests and the debug time-warp.
    func advance(by delta: TimeInterval) {
        let now = state.now
        lastAdvanceAt = Date()

        if combo.prune(at: now) { objectWillChange.send() }
        expireGoldenIfNeeded(now: now)
        expireOrderIfNeeded(now: now)
        finishRushIfNeeded(now: now)
        settleGauntletIfFinished(now: now)

        var serves: [Int: ServeEvent] = [:]
        var totalServed = 0
        let multiplier = payoutMultiplier
        var earned: Double = 0

        for venue in Balance.venues where state.venues[venue.id].unlocked {
            for spec in venue.stations {
                var station = state.venues[venue.id].stations[spec.id]
                guard station.isOwned else { continue }

                // Resolve the station's modifiers once. Each of cycleTime/baseRevenue
                // recomputes them internally, and they walk every manager in the venue, so
                // calling all three per station tripled the work on every tick.
                let mods = state.modifiers(venue: venue.id, station: spec.id)
                modifiersCache[StationKey(venue: venue.id, station: spec.id)] = mods
                let cycle = max(Balance.minimumCycle,
                                Balance.cycleTime(spec: spec, level: station.level) / mods.speed)
                let revenue = Balance.revenuePerCycle(spec: spec, level: station.level)
                    * mods.profit * multiplier

                if station.isStaffed {
                    station.isRunning = true
                    station.elapsed += delta
                    let completions = floor(station.elapsed / cycle)
                    if completions > 0 {
                        station.elapsed -= completions * cycle
                        let served = Int(completions)
                        let payout = revenue * completions * doubleServeFactor(mods, servings: served)
                        earned += payout
                        totalServed += served
                        advanceCatering(venue: venue.id, station: spec.id, served: served)
                        if venue.id == state.currentVenue {
                            serves[spec.id] = ServeEvent(station: spec.id, amount: payout, count: served)
                        }
                    }
                } else if station.isRunning {
                    station.elapsed += delta
                    if station.elapsed >= cycle {
                        station.elapsed = 0
                        station.isRunning = false
                        let payout = revenue * doubleServeFactor(mods, servings: 1)
                        earned += payout
                        totalServed += 1
                        advanceCatering(venue: venue.id, station: spec.id, served: 1)
                        if venue.id == state.currentVenue {
                            serves[spec.id] = ServeEvent(station: spec.id, amount: payout, count: 1)
                        }
                    }
                }

                state.venues[venue.id].stations[spec.id] = station
            }
        }

        if earned > 0 {
            state.coins += earned
            recordEarnings(earned)
        }
        if totalServed > 0 {
            registerServed(totalServed)
        }
        if !serves.isEmpty {
            for (station, event) in serves {
                var pending = pendingBursts[station] ?? (amount: 0, count: 0)
                pending.amount += event.amount
                pending.count += event.count
                pendingBursts[station] = pending
            }
            servedCustomers += totalServed
            fulfillOrderIfServed(serves, now: now)
        }
        flushBursts()

        League.advanceRivals(&state.league, to: now, playerRate: state.automatedRate)
        // Both of these used to be checked only on foreground, so a season or a league week
        // that ended while the app was open just sat there until the next relaunch.
        settleLeagueIfFinished()
        Festival.rolloverIfNeeded(&state.festival, now: now)
    }

    /// Releases pooled payouts, at most one burst per station per interval, so each animation
    /// gets to finish and the number shown is the whole take since the last one.
    private func flushBursts() {
        guard !pendingBursts.isEmpty else { return }
        let now = CACurrentMediaTimeCompat()

        for station in Array(pendingBursts.keys) {
            let last = lastBurstAt[station] ?? -.greatestFiniteMagnitude
            guard now - last >= Self.burstMinimumInterval else { continue }
            guard let pending = pendingBursts.removeValue(forKey: station) else { continue }
            lastBurstAt[station] = now
            lastServe[station] = ServeEvent(station: station, amount: pending.amount,
                                            count: pending.count)
        }
    }

    /// Expected multiplier from the double-serve perk over N servings.
    private func doubleServeFactor(_ mods: StationModifiers, servings: Int) -> Double {
        guard mods.doubleServeChance > 0 else { return 1 }
        // Bulk completions use the expected value; a single serve rolls for real so the
        // player actually sees the occasional double.
        if servings > 1 { return 1 + mods.doubleServeChance }
        return Double.random(in: 0..<1, using: &rng) < mods.doubleServeChance ? 2 : 1
    }

    private func recordEarnings(_ amount: Double) {
        state.lifetimeEarnings += amount
        state.runEarnings += amount
        state.league.score += amount
        if gauntletActive { state.gauntletScore += amount }
        advanceQuests(kind: .earn, by: amount)
        registerLandmarks()
    }

    private func registerLandmarks() {
        // Only checks against the current total, not "did this specific increment cross it" -
        // a single big jump (a long-offline catch-up, an 8h time warp, a fat quest/catering
        // payout) can clear more than one landmark at once. The old `before < value` check
        // only fired for whichever landmark that jump happened to land past FIRST, and since
        // lifetimeEarnings only ever grows, every other landmark inside that same jump would
        // find `before` already past it on every future call too - permanently un-celebrated
        // and permanently missing from landmarksCrossed, not just delayed. This still only
        // celebrates one per call (`break`), but the next call - even a one-coin serve - now
        // correctly picks up wherever the celebration left off instead of stranding it.
        for exponent in GameState.landmarkExponents where !state.landmarksCrossed.contains(exponent) {
            let value = pow(10, Double(exponent))
            if state.lifetimeEarnings >= value {
                state.landmarksCrossed.insert(exponent)
                pendingLandmark = value
                break // one celebration at a time; the next crossing re-fires
            }
        }
    }

    private func registerServed(_ count: Int) {
        state.totalServed += count
        advanceQuests(kind: .serve, by: Double(count))

        // Festival tickets drip from serving, up to a per-season ceiling. Without the cap
        // an established player's serve rate alone finished the whole track in minutes.
        state.festival.serveCounter += count
        let per = Festival.servesPerTicket
        if state.festival.serveCounter >= per {
            let tickets = state.festival.serveCounter / per
            state.festival.serveCounter %= per
            let scaled = Int((Double(tickets) * state.researchEffects.ticketMultiplier
                              * state.toolEffects.ticketMultiplier).rounded())
            let headroom = Swift.max(0, Festival.maxTicketsFromServing - state.festival.ticketsFromServing)
            let granted = Swift.min(scaled, headroom)
            if granted > 0 {
                state.festival.ticketsFromServing += granted
                awardTickets(granted)
            }
        }
    }

    // MARK: Multipliers

    var comboMultiplier: Double {
        combo.isLive(at: state.now) ? combo.multiplier(maxSteps: state.comboMaxSteps) : 1
    }

    /// Everything that scales a payout right now, including the transient combo and the
    /// daily Happy Hour window.
    var payoutMultiplier: Double {
        var multiplier = state.globalMultiplier * comboMultiplier
            * (state.isHappyHour() ? ActivePlay.happyHourMultiplier : 1)
        if gauntletActive {
            multiplier *= gauntletPayoutBonus
            // Hands Only: the sprint pays x3 on everything WHILE the combo is alive -
            // taps are the whole game for those ten minutes.
            if gauntletMutator.id == "handsonly", combo.isLive(at: state.now) {
                multiplier *= 3
            }
        }
        return multiplier
    }

    /// What golden tips and order bonuses scale by: everything in `payoutMultiplier` except
    /// the tap combo. The combo exists to reward mashing on station income; letting it also
    /// quintuple a "45 seconds of income" tip turned every caught VIP into minutes of
    /// income and made goldens the dominant early-game money source.
    var tipMultiplier: Double {
        payoutMultiplier / comboMultiplier
    }

    var incomePerSecond: Double {
        state.automatedRate * activeBoostMultiplier * comboMultiplier
            * (state.isHappyHour() ? ActivePlay.happyHourMultiplier : 1)
    }

    private var activeBoostMultiplier: Double {
        state.activeBoosts.reduce(1.0) { $0 * $1.multiplier }
    }

    // MARK: Player actions

    @discardableResult
    func tap(station index: Int) -> Bool {
        let venue = state.currentVenue
        guard state.venues[venue].stations.indices.contains(index) else { return false }

        // Every tap feeds the combo, even on a staffed station - otherwise automation kills
        // the reason to hold the phone.
        combo.register(at: state.now, windowBonus: state.comboWindowBonus(venue: venue))
        state.totalTaps += 1
        advanceQuests(kind: .tap, by: 1)
        state.tutorial.complete(.tapStation)
        // Tap Frenzy seasons: taps drip festival tickets too (through the same serve-track
        // cap as everything else, so the season can't blow the track open).
        if let per = Festival.modifier(seasonID: state.festival.seasonID).tapsPerTicket,
           state.totalTaps % per == 0 {
            let headroom = Swift.max(0, Festival.maxTicketsFromServing - state.festival.ticketsFromServing)
            if headroom > 0 {
                state.festival.ticketsFromServing += 1
                awardTickets(1)
            }
        }

        var station = state.venues[venue].stations[index]
        guard station.isOwned, !station.isStaffed, !station.isRunning else { return false }
        station.isRunning = true
        station.elapsed = 0
        state.venues[venue].stations[index] = station
        return true
    }

    /// Hours since the current board (last Franchise/Legacy reset, or save creation) began.
    var boardAgeHours: Double { state.now.timeIntervalSince(state.boardStartedAt) / 3600 }

    /// How much pricier every purchase on this board is right now: the staleness tax (see
    /// `Balance.stalenessMultiplier`) times the player's own star multiplier - the exact
    /// same factor `automatedRate` multiplies income by. Before this, a fresh post-prestige
    /// board charged first-timer prices while paying out at the player's permanent,
    /// star-boosted rate: a live report showed a second prestige landing minutes after the
    /// first (100B lifetime earnings to reach it, ~2.56 quintillion for the next, both
    /// inside the same short session) - the star bonus is meant to make every RUN feel more
    /// powerful forever, not compound into a same-session runaway by racing ahead of costs
    /// that never caught up. Matching the two factors cancels out in the pace math (cost*N)
    /// / (rate*N) = cost/rate unchanged, so run-to-run speed stays roughly what it was
    /// before a player had any stars, while the numbers themselves keep growing - the
    /// feeling prestige is supposed to give.
    var costInflation: Double { staleCostInflation * Balance.starMultiplier(stars: state.lifetimeStars) }

    /// The staleness portion alone - what the "costs are up, go prestige" UI badges (the
    /// Stations header, the Franchise sheet) should read, not the combined `costInflation`.
    /// A reset zeroes this back to 1x, which is what that copy promises; it can't do the
    /// same for the star-multiplier portion, since lifetimeStars is permanent by design -
    /// showing the full combined number there would make "reset for normal prices" a lie
    /// for anyone who has ever prestiged.
    ///
    /// Held at 1x for as long as `allVenuesAndStationsUnlocked` is false - the tax exists to
    /// punish a player who COULD prestige and is choosing to stall, not one who is working as
    /// fast as possible toward a gate they cannot yet pass. Since that gate now requires the
    /// whole board finished (see `canPrestige`), and finishing it is itself the thing this tax
    /// would otherwise be taxing, letting it run during the mandatory rebuild created a
    /// feedback loop with no exit: a calibration run against the real venue-unlock curve found
    /// venue 5 never unlocking inside 150 simulated hours because the tax had already inflated
    /// every cost roughly 15,000x by the time the board reached it. `prestige()` wipes the
    /// board and re-requires full completion on every cycle, not just the first, so this
    /// exemption applies every cycle's rebuild - not only before the player's first-ever
    /// prestige.
    var staleCostInflation: Double {
        guard allVenuesAndStationsUnlocked else { return 1 }
        return Balance.stalenessMultiplier(
            boardAgeHours: boardAgeHours,
            graceBonusHours: (state.contract?.staleGraceDeltaHours ?? 0)
                + state.legacyEffects.staleGraceBonusHours)
    }

    func quantity(for index: Int, in venue: Int? = nil) -> Int {
        let venueID = venue ?? state.currentVenue
        let spec = Balance.venue(venueID).stations[index]
        let level = state.venues[venueID].stations[index].level
        // Unlocking is always a single, fixed action, whatever buy-quantity mode happens to
        // be selected - a live report caught the actual bug this masked: with MAX picked, a
        // locked station's shown price was "as many levels as you can currently afford from
        // zero", which visibly grew every time coins did (read as "a % of money" rather than
        // a real price). x10/x100/NEXT had the same category of problem, just less visibly,
        // since a fixed 10x/100x/next-milestone jump makes just as little sense for a button
        // that only ever says "UNLOCK".
        guard level > 0 else { return 1 }
        if let fixed = buyQuantity.fixedAmount { return fixed }
        if buyQuantity == .next {
            // Exactly enough to land ON the next milestone level, not past it - the whole
            // point is buying precisely up to the payoff. No milestone left (level 2000+)
            // falls back to a single level, same as if NEXT weren't selected at all.
            guard let next = Balance.nextMilestone(level: level) else { return 1 }
            return Swift.max(1, next.level - level)
        }
        // Multiplying every cost by `costInflation` is equivalent to dividing spending power
        // by it when inverting for an affordable quantity - keeps Balance's closed-form cost
        // curve untouched and correct for any inflation level.
        return Swift.max(1, Balance.maxAffordable(spec: spec, level: level, coins: state.coins / costInflation))
    }

    func price(for index: Int, in venue: Int? = nil) -> Double {
        let venueID = venue ?? state.currentVenue
        let spec = Balance.venue(venueID).stations[index]
        let level = state.venues[venueID].stations[index].level
        return Balance.cost(spec: spec, level: level, quantity: quantity(for: index, in: venueID)) * costInflation
    }

    func canAfford(index: Int) -> Bool { state.coins >= price(for: index) }

    @discardableResult
    func buy(station index: Int) -> Bool {
        let venue = state.currentVenue
        let amount = quantity(for: index)
        let cost = price(for: index)
        guard amount > 0, state.coins >= cost else { return false }

        state.coins -= cost
        let levelBefore = state.venues[venue].stations[index].level
        state.venues[venue].stations[index].level += amount

        state.tutorial.complete(.buyLevel)
        // The free first-station hire (see eligibleForFreeFirstManager) has no prerequisite -
        // a player can claim it before tapping or buying anything at all. If they do, station
        // 0 is already staffed by the time the tutorial would normally reach this step, so its
        // target (a hire button that no longer exists there) is gone before the step even
        // starts, and nothing else may be unlocked yet to hire instead. Skip it the same way
        // coffeeBreak already does below when its own target isn't actionable.
        if state.tutorial.current == .hireManager,
           state.venues[venue].stations.contains(where: { $0.isStaffed }) {
            state.tutorial.complete(.hireManager)
            // Chained for the same reason hireManager() below checks it: a new save locks
            // Coffee Break out for its first 15 minutes, so skipping straight into a step
            // that's also not actionable yet would just trade one stuck step for another.
            if state.tutorial.current == .coffeeBreak, !boostReady {
                state.tutorial.complete(.coffeeBreak)
            }
        }
        rollRecipe(venue: venue, station: index, levels: amount)
        advanceQuests(kind: .level, to: Double(Quests.highestStationLevel(state)))
        checkPerkUnlock(venue: venue, station: index, levelBefore: levelBefore)
        checkVenueMastery(venue: venue)
        return true
    }

    /// Bronze/silver/gold per venue for every station reaching Lv 50/100/250 at once.
    /// Persisted in `venueMastery` because it's an accomplishment, not board state -
    /// prestige wipes the levels but never the badge.
    static let masteryThresholds = [50, 100, 250]

    private func checkVenueMastery(venue id: Int) {
        let stations = state.venues[id].stations
        guard stations.allSatisfy(\.isOwned) else { return }
        let weakest = stations.map(\.level).min() ?? 0
        let tier = Self.masteryThresholds.filter { weakest >= $0 }.count
        let current = state.venueMastery[id] ?? 0
        guard tier > current else { return }
        state.venueMastery[id] = tier
        let names = ["", "Bronze", "Silver", "Gold"]
        toast = "\(Balance.venue(id).name): \(names[tier]) Mastery!"
    }

    func managerCost(for index: Int) -> Double {
        managerCost(for: index, venue: state.currentVenue)
    }

    /// Venue-aware variant for call sites that can target a station outside the venue
    /// currently on screen, like reassigning a bench manager from the Staff sheet.
    func managerCost(for index: Int, venue: Int) -> Double {
        Balance.managerCost(spec: Balance.venue(venue).stations[index]) * costInflation
    }

    /// Station 0's very first manager is always free - a new save starts with only 25 gems,
    /// well under the instant-hire gem price, and may not have saved up the coin cost either
    /// right after the tutorial's own buy-a-level step. This used to be gated on the tutorial
    /// overlay's current step, which meant a player who dismissed the tutorial before reaching
    /// this step lost the free hire entirely - and `state.freeFirstManagerClaimed` (rather than
    /// tutorial state) is what remembers it's been used, since `TutorialState.complete(_:)`
    /// no-ops entirely once `finished` is true, which would otherwise re-offer a free manager
    /// after every future Franchise reset for anyone who ever skipped the tutorial.
    func eligibleForFreeFirstManager(station index: Int) -> Bool {
        index == 0 && !state.freeFirstManagerClaimed
    }

    @discardableResult
    func hireManager(for index: Int, free: Bool = false, premium: Bool = false) -> Bool {
        let venue = state.currentVenue
        guard state.venues[venue].stations.indices.contains(index) else { return false }
        let station = state.venues[venue].stations[index]
        guard station.isOwned, !station.isStaffed else { return false }
        // Gated on `free` itself, not just eligibility: burning the entitlement on any
        // eligible call regardless of whether it was actually free would let a caller that
        // forgets the flag charge the player AND silently spend their one free hire in the
        // same call - now a mis-flagged call just charges normally and leaves the free hire
        // available for whichever call remembers to ask for it.
        if free, eligibleForFreeFirstManager(station: index) {
            state.freeFirstManagerClaimed = true
        }
        let cost = managerCost(for: index)
        if !free {
            guard state.coins >= cost else { return false }
            state.coins -= cost
        }
        state.hire(specID: ManagerCatalog.traineeID, venue: venue, station: index, premium: premium)
        advanceQuests(kind: .hire, to: Double(state.assignedManagerCount))
        // The free first-manager hire (see eligibleForFreeFirstManager) has no prerequisite -
        // a player can claim it before ever tapping or buying a level. When they do, the
        // station is staffed and auto-running before the tutorial ever reached tapStation or
        // buyLevel, so neither target's real-world condition will ever become true: tapping an
        // already-staffed station is a no-op, and there's no reason to manually buy a level
        // that's already earning on its own. Skip straight through whatever's still ahead of
        // hireManager instead of leaving the overlay stuck asking for an action the player has
        // no way, or reason, to perform.
        while let current = state.tutorial.current, current.rawValue < TutorialStep.hireManager.rawValue {
            state.tutorial.complete(current)
        }
        state.tutorial.complete(.hireManager)
        // A new save locks Coffee Break out for its first 15 minutes, so the very next
        // tutorial step would instruct the player to tap something that's visibly disabled.
        // Skip straight past it instead of ever showing a step that can't be followed.
        if state.tutorial.current == .coffeeBreak, !boostReady {
            state.tutorial.complete(.coffeeBreak)
        }
        return true
    }

    /// Moving a manager onto a station charges the same one-time staffing fee as hiring fresh
    /// UNLESS that station has been staffed before - reshuffling an existing roster between
    /// stations you already paid to open stays free. Returns whether the assignment happened,
    /// so a bulk caller like `autoAssignBenchedManagers` can tell a real placement from a
    /// station the player can't yet afford to staff.
    @discardableResult
    func assign(managerID: String?, venue: Int, station: Int) -> Bool {
        // Every other station-indexed entry point (hireManager, buy, managerCost) validates
        // its index before touching state; this one didn't, so an out-of-range venue/station
        // - unlikely from the shipped UI, which only ever offers valid indices, but reachable
        // from any future caller - would crash on the array subscript below instead of
        // failing gracefully like its siblings.
        guard state.venues.indices.contains(venue),
              state.venues[venue].stations.indices.contains(station) else { return false }
        if let managerID, !state.venues[venue].stations[station].everStaffed {
            let cost = managerCost(for: station, venue: venue)
            guard state.coins >= cost else {
                toast = "Need \(Format.price(cost)) to staff \(Balance.venue(venue).stations[station].name)"
                return false
            }
            state.coins -= cost
        }
        state.assign(managerID: managerID, venue: venue, station: station)
        if managerID != nil { advanceQuests(kind: .hire, to: Double(state.assignedManagerCount)) }
        return true
    }

    /// Fills every open (owned, unstaffed) station across every unlocked venue with a
    /// benched manager, first-open-station to first-available-manager - no strategy beyond
    /// that, since this is a convenience for "I have idle staff and open stations, just put
    /// them to work," not a placement optimizer. A player who wants a SPECIFIC manager on a
    /// SPECIFIC station still assigns that one by hand; this only ever touches stations that
    /// were sitting empty. Returns how many assignments were made.
    @discardableResult
    func autoAssignBenchedManagers() -> Int {
        var bench = state.unassignedManagers
        guard !bench.isEmpty else { return 0 }
        var assigned = 0
        for venue in Balance.venues where state.venues[venue.id].unlocked {
            for spec in venue.stations {
                guard let manager = bench.first else { return assigned }
                let station = state.venues[venue.id].stations[spec.id]
                guard station.isOwned, !station.isStaffed else { continue }
                // Only consumes the bench manager on a real placement - one who can't afford
                // this station's first-time staffing fee stays on the bench and gets tried
                // against the next open station instead of vanishing.
                if assign(managerID: manager.id, venue: venue.id, station: spec.id) {
                    bench.removeFirst()
                    assigned += 1
                }
            }
        }
        return assigned
    }

    /// Adds staff from a reward source and reports who turned up. Always premium - these are
    /// rare, one-off grants (festival, league, IAP), never the coin-grind staffing loop.
    @discardableResult
    func grantManager(rarity: ManagerRarity) -> ManagerSpec {
        let spec = ManagerCatalog.random(rarity: rarity, seed: Int.random(in: 0..<10_000, using: &rng))
        state.recruit(specID: spec.id, premium: true)
        return spec
    }

    // MARK: Guest Chef

    var currentGuestChef: ManagerSpec { GuestChef.current(now: state.now) }

    var guestChefAlreadyPurchasedThisWeek: Bool {
        state.lastGuestChefPurchaseWeek == GuestChef.weekKey(now: state.now)
    }

    /// True the first time the Staff sheet is opened for a given week's pick - drives a
    /// one-shot celebration rather than replaying it on every visit.
    var guestChefSpotlightPending: Bool {
        state.lastGuestChefSpotlightWeek != GuestChef.weekKey(now: state.now)
    }

    func markGuestChefSpotlightSeen() {
        state.lastGuestChefSpotlightWeek = GuestChef.weekKey(now: state.now)
        save()
    }

    @discardableResult
    func purchaseGuestChef() -> ManagerSpec? {
        guard !guestChefAlreadyPurchasedThisWeek else { return nil }
        guard spendGems(GuestChef.gemPrice) else { return nil }
        let spec = currentGuestChef
        state.recruit(specID: spec.id, premium: true)
        state.lastGuestChefPurchaseWeek = GuestChef.weekKey(now: state.now)
        save()
        return spec
    }

    // MARK: Perks

    var perkChoicesRemaining: Int {
        Swift.max(0, Balance.perkChoicesPerRun - state.perkChoicesUsed)
    }

    /// Auto-opens the perk picker only when this buy newly crossed a choice level. A player
    /// who tapped "Decide later" must be able to keep upgrading in peace - the deferred
    /// choice stays reachable through the station row's PERK button, not by hijacking every
    /// subsequent purchase with the sheet again.
    private func checkPerkUnlock(venue: Int, station: Int, levelBefore: Int) {
        guard perkChoicesRemaining > 0 else { return }
        let s = state.venues[venue].stations[station]
        let crossedNewChoice = Perks.choiceLevels.contains {
            levelBefore < $0 && s.level >= $0 && s.perks[$0] == nil
        }
        if crossedNewChoice, venue == state.currentVenue {
            pendingPerkStation = station
        }
    }

    func pendingPerkLevel(venue: Int, station: Int) -> Int? {
        guard perkChoicesRemaining > 0 else { return nil }
        let s = state.venues[venue].stations[station]
        return Perks.pending(level: s.level, chosen: s.perks)
    }

    func choosePerk(venue: Int, station: Int, level: Int, index: Int) {
        // A perk once chosen at this level can't be chosen again - without this, a double-tap
        // in the moment between confirming and the sheet's dismiss animation burns a second
        // one of the run's four precious choices for no extra effect.
        guard state.venues[venue].stations[station].perks[level] == nil else { return }
        guard perkChoicesRemaining > 0 else { return }
        state.venues[venue].stations[station].perks[level] = index
        state.perkChoicesUsed += 1
        pendingPerkStation = nil
        save()
    }

    // MARK: Recipes

    private func rollRecipe(venue: Int, station: Int, levels: Int) {
        let drop = Recipes.roll(cards: &state.recipeCards, venue: venue, station: station,
                                levelsBought: levels, random: Double.random(in: 0..<1, using: &rng))
        switch drop {
        case .none:
            return
        case .duplicateGems(let gems):
            state.gems += gems
        case .newCard, .upgraded:
            advanceQuests(kind: .recipes, to: Double(Recipes.totalCollected(state.recipeCards)))
        }
        lastRecipeDrop = drop
    }

    // MARK: Signature Dish (recipe fusion)

    /// A venue whose whole recipe set is 3-starred may crown one station its Signature
    /// Dish (x1.5 profit there). Re-crownable freely - a standing strategy knob that gives
    /// the recipe album an endgame beyond set completion.
    func canCrownSignature(venue: Int) -> Bool {
        Balance.venue(venue).stations.allSatisfy {
            Recipes.stars(state.recipeCards, venue: venue, station: $0.id) >= Recipes.maxStars
        }
    }

    @discardableResult
    func crownSignatureDish(venue: Int, station: Int) -> Bool {
        guard canCrownSignature(venue: venue),
              Balance.venue(venue).stations.indices.contains(station) else { return false }
        state.signatureDish[venue] = station
        save()
        return true
    }

    // MARK: Rush Hour

    var rushActive: Bool { state.isRushActive(at: state.now) }
    var rushReady: Bool { state.rushReady(at: state.now) }
    var rushRemaining: TimeInterval { state.rushRemaining(at: state.now) }
    var rushCooldownRemaining: TimeInterval { state.rushCooldownRemaining(at: state.now) }

    /// Chain tier for the Rush about to start: returning within an hour of the cooldown
    /// ending keeps the chain alive (max 3), each tier adding +25% to the Rush multiplier.
    /// An appointment mechanic on a system that already exists - punctuality pays.
    private func nextRushChain(now: Date) -> Int {
        let punctual = now <= state.rushAvailableAt.addingTimeInterval(ActivePlay.rushChainWindowSeconds)
        return punctual ? min(ActivePlay.rushChainMax, state.rushChain + 1) : 1
    }

    var rushChainMultiplier: Double {
        ActivePlay.rushMultiplier * (1 + 0.25 * Double(max(0, state.rushChain - 1)))
    }

    @discardableResult
    func startRush(force: Bool = false) -> Bool {
        guard force || rushReady else { return false }
        let now = state.now
        state.rushChain = nextRushChain(now: now)
        let multiplier = rushChainMultiplier
        state.rushEndsAt = now.addingTimeInterval(state.rushDuration)
        state.rushAvailableAt = state.rushEndsAt
            .addingTimeInterval(ActivePlay.rushCooldownMinutes * 60)
        let label = state.rushChain > 1
            ? "Rush ×\(Format.trim(multiplier)) · Chain \(state.rushChain)"
            : "Rush ×\(Format.trim(multiplier))"
        Boosts.add(BoostState(id: ActivePlay.rushBoostID, label: label,
                              multiplier: multiplier, expiry: state.rushEndsAt), to: &state)
        return true
    }

    private func finishRushIfNeeded(now: Date) {
        guard state.rushEndsAt != .distantPast, state.rushEndsAt <= now else { return }
        state.rushEndsAt = .distantPast
        state.rushesCompleted += 1
        advanceQuests(kind: .rush, by: 1)
        awardTickets(Festival.ticketsPerRush)
        rollToolDrop(.rushComplete)
        toast = "Rush Hour complete"
    }

    // MARK: Golden customer

    /// The last time each treat actually spawned. In-memory only: the worst a relaunch can
    /// do is let one spawn arrive early, which isn't worth a save-format field.
    private var lastGoldenSpawnAt = Date.distantPast
    private var lastOrderSpawnAt = Date.distantPast

    /// Called by the queue each time it rotates a customer out.
    func rollGoldenCustomer() {
        guard golden == nil, state.automatedRate > 0 || state.coins > 0 else { return }
        guard state.now.timeIntervalSince(lastGoldenSpawnAt) >= ActivePlay.goldenCooldown else { return }
        let chance = state.goldenChance * (state.isHappyHour() ? 2 : 1)
            * Festival.modifier(seasonID: state.festival.seasonID).goldenChanceMultiplier
            * gauntletGoldenBonus
        guard Double.random(in: 0..<1, using: &rng) < chance else { return }
        lastGoldenSpawnAt = state.now
        golden = GoldenCustomer(seed: Int.random(in: 0..<10_000, using: &rng),
                                expiresAt: state.now.addingTimeInterval(ActivePlay.goldenWindow),
                                isCritic: Double.random(in: 0..<1, using: &rng) < ActivePlay.criticChance)
    }

    private func expireGoldenIfNeeded(now: Date) {
        if let current = golden, current.expiresAt <= now { golden = nil }
    }

    /// Pays out 15-45 seconds of income for catching the VIP in time - x10 for a critic.
    @discardableResult
    func collectGolden() -> Double {
        guard let customer = golden else { return 0 }
        golden = nil
        let seconds = Double.random(in: ActivePlay.goldenMinSeconds...ActivePlay.goldenMaxSeconds, using: &rng)
        let base = Swift.max(state.automatedRate, ActivePlay.tipFloorRate(venue: state.currentVenue))
        var amount = base * seconds * tipMultiplier
        if customer.isCritic {
            amount *= ActivePlay.criticMultiplier
            toast = "VIP CRITIC! ×\(Int(ActivePlay.criticMultiplier)) tip: \(Format.currency(amount))"
        }
        addCoins(amount)
        rollToolDrop(.goldenCollect)
        return amount
    }

    // MARK: Customer orders

    /// Called by the queue each time it rotates a customer out, alongside rollGoldenCustomer.
    func rollStationOrder() {
        guard activeOrder == nil else { return }
        guard state.now.timeIntervalSince(lastOrderSpawnAt) >= ActivePlay.orderCooldown else { return }
        let venue = state.currentVenue
        let staffed = Balance.venue(venue).stations
            .filter { state.venues[venue].stations[$0.id].isStaffed }
            .map(\.id)
        guard !staffed.isEmpty else { return }
        guard Double.random(in: 0..<1, using: &rng) < ActivePlay.orderBaseChance else { return }
        lastOrderSpawnAt = state.now
        let station = staffed.randomElement(using: &rng) ?? staffed[0]
        activeOrder = StationOrder(venue: venue, station: station,
                                   expiresAt: state.now.addingTimeInterval(ActivePlay.orderWindow))
    }

    private func expireOrderIfNeeded(now: Date) {
        if let order = activeOrder, order.expiresAt <= now { activeOrder = nil }
    }

    /// Pays a coin bonus when the ordered station serves within the window. Called from
    /// advance(by:) right after the per-station loop, using the same `serves` dictionary it
    /// already built for burst animations.
    private func fulfillOrderIfServed(_ serves: [Int: ServeEvent], now: Date) {
        guard let order = activeOrder, order.venue == state.currentVenue,
              serves[order.station] != nil else { return }
        activeOrder = nil
        let seconds = Double.random(in: ActivePlay.orderBonusMinSeconds...ActivePlay.orderBonusMaxSeconds, using: &rng)
        let base = Swift.max(state.automatedRate, ActivePlay.tipFloorRate(venue: state.currentVenue))
        addCoins(base * seconds * tipMultiplier)
    }

    // MARK: Venues

    var nextLockedVenue: VenueSpec? {
        Balance.venues.first { !state.venues[$0.id].unlocked }
    }

    /// The venue's base price, inflated by however stale the current board is - matches every
    /// other purchase on the board (see `costInflation`), so opening a new venue doesn't
    /// become the one loophole around the staleness tax.
    func unlockCost(for venue: VenueSpec) -> Double {
        venue.unlockCost * costInflation * (state.contract?.venueUnlockCostMultiplier ?? 1)
    }

    func canUnlock(_ venue: VenueSpec) -> Bool { state.coins >= unlockCost(for: venue) }

    @discardableResult
    func unlock(_ venue: VenueSpec) -> Bool {
        guard !state.venues[venue.id].unlocked, canUnlock(venue) else { return false }
        state.coins -= unlockCost(for: venue)
        state.venues[venue.id].unlocked = true
        state.venues[venue.id].stations[0].level = 1
        switchTo(venue: venue.id)
        return true
    }

    func switchTo(venue id: Int) {
        guard state.venues.indices.contains(id), state.venues[id].unlocked else { return }
        state.currentVenue = id
        lastServe.removeAll()
        pendingBursts.removeAll()
        lastBurstAt.removeAll()
        golden = nil
        activeOrder = nil
    }

    // MARK: Cosmetics

    /// Purely visual, so priced in coins rather than gems - it can't cut against the "never
    /// sell power" line the rest of the shop holds to.
    func skinPrice(venue: Int) -> Double {
        Balance.venue(venue).stations[0].baseCost * 500
    }

    @discardableResult
    func unlockSkin(venue: Int, skin: String) -> Bool {
        guard skin != "classic", !state.hasUnlockedSkin(venue: venue, skin: skin) else { return false }
        let price = skinPrice(venue: venue)
        guard state.coins >= price else { return false }
        state.coins -= price
        state.unlockedSkins[venue, default: []].insert(skin)
        state.venueSkins[venue] = skin
        save()
        return true
    }

    /// Re-equips an already-unlocked skin for free - only the first unlock costs coins.
    @discardableResult
    func setSkin(venue: Int, skin: String) -> Bool {
        guard state.hasUnlockedSkin(venue: venue, skin: skin) else { return false }
        state.venueSkins[venue] = skin
        save()
        return true
    }

    // MARK: Prestige

    var pendingStars: Int {
        Balance.pendingStars(lifetimeEarnings: state.lifetimeEarnings, currentStars: state.lifetimeStars)
    }

    /// A hard floor on top of the earnings gate below: every venue open, every station in
    /// every venue owned. Deliberately stricter than `boardIsFullyBuiltOut`, which is
    /// satisfied the moment the *next* venue is merely unaffordable and only checks staffing
    /// on venues already unlocked - this checks literal completion, all seven venues, station
    /// ownership rather than staffing. Since a Franchise reset wipes venues back to just
    /// Burger Shack (see `prestige()`), this floor applies to every run, not only the first.
    var allVenuesAndStationsUnlocked: Bool {
        Balance.venues.allSatisfy { venue in
            state.venues[venue.id].unlocked
                && state.venues[venue.id].stations.allSatisfy(\.isOwned)
        }
    }

    var canPrestige: Bool {
        pendingStars > 0
            && state.lifetimeEarnings >= Balance.minimumLifetimeForPrestige
            && allVenuesAndStationsUnlocked
    }

    /// Every unlocked venue fully built out - staffed on every station - with nowhere left
    /// to spend coins: either every venue is open, or the next one is unaffordable. A player
    /// in this state has nothing actionable left on the board itself; prestige is the only
    /// remaining move.
    var boardIsFullyBuiltOut: Bool {
        let unlocked = Balance.venues.filter { state.venues[$0.id].unlocked }
        guard !unlocked.isEmpty else { return false }
        let allStaffed = unlocked.allSatisfy { venue in
            state.venues[venue.id].stations.allSatisfy { $0.isOwned && $0.isStaffed }
        }
        guard allStaffed else { return false }
        guard let next = nextLockedVenue else { return true }
        return !canUnlock(next)
    }

    /// Surfaces the prestige entry point beyond just the HUD pill being visible: either this
    /// is the player's first time being eligible, or they've plateaued on the current board
    /// with nothing left to build - both are moments a player can plausibly not know
    /// prestige exists, or forget it does.
    var shouldNudgePrestige: Bool {
        canPrestige && (state.prestigeCount == 0 || boardIsFullyBuiltOut)
    }

    /// First-time pulse on the Venues tab: the moment venue 2 becomes affordable is the
    /// first big decision after the tutorial, and it used to have no signpost beyond a
    /// red dot. One-shot; marked seen when the Venues sheet opens.
    var shouldNudgeSecondVenue: Bool {
        state.tutorial.finished
            && state.venues.filter(\.unlocked).count == 1
            && nextLockedVenue.map(canUnlock) == true
            && !hasSeenIntro(IntroKey.venueNudge)
    }

    /// True once a never-prestiged player crosses half the first-Franchise minimum - the
    /// late tutorial beat that names the "real game" while it's finally close enough to
    /// feel real. One-shot via `IntroKey.halfwayFranchise`; RootView watches this.
    var halfwayToFirstFranchise: Bool {
        state.prestigeCount == 0
            && state.lifetimeEarnings >= Balance.minimumLifetimeForPrestige * 0.5
    }

    @discardableResult
    func prestige() -> Int {
        guard canPrestige else { return 0 }
        // Star-award bonuses (Investor Showcase contract, Master Negotiator legacy perk)
        // pay on top of the formula. The formula's own pendingStars self-corrects: the
        // extra stars simply mean the next award arrives a little later.
        let bonus = (state.contract?.starAwardBonus ?? 0) + state.legacyEffects.starAwardBonus
        let award = Int((Double(pendingStars) * (1 + bonus)).rounded(.down))
        guard award > 0 else { return 0 }
        let preRate = state.automatedRate

        lastRunRecap = RunRecap(
            duration: state.now.timeIntervalSince(state.boardStartedAt),
            earned: state.runEarnings,
            served: state.totalServed - state.servedAtBoardStart,
            starsAwarded: award,
            prestigeNumber: state.prestigeCount + 1
        )
        state.servedAtBoardStart = state.totalServed
        state.stars += award            // spendable
        state.lifetimeStars += award    // permanent multiplier
        state.lastPrestigeAward = award // prices the next research ranks
        state.prestigeCount += 1
        state.coins = 0
        state.runEarnings = 0
        state.perkChoicesUsed = 0
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        state.venues[0].stations[0].level = 1
        state.currentVenue = 0
        state.boardStartedAt = state.now
        // Recipes and research survive a franchise reset - they're collections the player
        // built, not station upgrades. Staff only partly does: gem-bought, IAP-granted, and
        // reward-granted managers stay, but anyone hired with plain coins (or the tutorial's
        // free first hire) is let go. Free instant reassignment of a whole persisted roster
        // was most of what made repeat prestige cycles run away - restaffing a reset board
        // now costs real coins and real time again, same as the very first time through.
        state.managers.removeAll { !$0.premium }
        let remainingIDs = Set(state.managers.map(\.id))
        state.errands.removeAll { !remainingIDs.contains($0.managerID) }
        lastServe.removeAll()
        pendingBursts.removeAll()
        lastBurstAt.removeAll()
        combo.reset()
        // A golden customer or station order rolled on the old board must not survive
        // onto the new one - switchTo and adoptCloudSave already clear these.
        golden = nil
        activeOrder = nil
        // The new run owes a Contract pick (nil = picker pending); Seed Capital banks a
        // slice of the OLD run's hourly rate, capped per stack so it jump-starts the
        // early board without skipping it.
        state.activeContract = Contracts.unchosenID
        applySeedCapital(preRate: preRate)
        save()
        return award
    }

    /// Legacy's Seed Capital perk: each stack banks up to an hour of pre-reset income,
    /// capped at venue 2's base unlock price per stack - enough to blitz the opening
    /// minutes, never enough to trivialize the board.
    private func applySeedCapital(preRate: Double) {
        let hours = state.legacyEffects.startingCapitalHours
        guard hours > 0 else { return }
        let capPerStack = Balance.venues[1].unlockCost
        state.coins += Swift.min(preRate * hours * 3600, capPerStack * hours)
    }

    // MARK: Franchise Contracts

    /// Non-nil when the current run still owes its Contract pick - RootView watches this.
    var pendingContractOffer: [FranchiseContract]? {
        guard state.prestigeCount > 0,
              state.activeContract == Contracts.unchosenID else { return nil }
        return Contracts.offer(prestigeCount: state.prestigeCount)
    }

    func chooseContract(_ id: String) {
        guard state.activeContract == Contracts.unchosenID,
              pendingContractOffer?.contains(where: { $0.id == id }) == true else { return }
        state.activeContract = id
        save()
    }

    // MARK: Legacy (second prestige layer)

    var canLegacyReset: Bool {
        state.prestigeCount - state.prestigeCountAtLegacy >= Balance.legacyUnlockPrestigeCount
    }

    /// Trades away the accumulated star multiplier for a permanently bigger one. Unlike
    /// `prestige()`, this clears stars, lifetimeStars, AND `lifetimeEarnings` - stars are
    /// computed from earnings, so leaving earnings meant one quick re-prestige restored
    /// the whole multiplier for free. The star climb genuinely restarts, which is why
    /// `Balance.legacyMultiplier` pays +20% per level. RESEARCH SURVIVES: the game
    /// promises everywhere that research is permanent knowledge (and sells stars on that
    /// promise), so Legacy's cost is the earnings/multiplier climb - weeks of momentum -
    /// never the tree. Managers, recipes, tools, achievements, errands, festival and
    /// league are also untouched: collections and accomplishments, not run progress.
    @discardableResult
    func legacyReset() -> Int {
        guard canLegacyReset else { return state.legacy.level }
        state.legacy.level += 1
        state.coins = 0
        state.runEarnings = 0
        state.perkChoicesUsed = 0
        state.lifetimeEarnings = 0
        state.stars = 0
        state.lifetimeStars = 0
        state.lastPrestigeAward = 0
        state.prestigeCountAtLegacy = state.prestigeCount
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        state.venues[0].stations[0].level = 1
        state.currentVenue = 0
        state.boardStartedAt = state.now
        // Legacy also starts a fresh board, same as prestige() - without this, the NEXT
        // Franchise reset's recap would report every dish served since the last Franchise
        // (which may be well before this Legacy reset) instead of just this run, since
        // RunRecap.served is totalServed - servedAtBoardStart.
        state.servedAtBoardStart = state.totalServed
        lastServe.removeAll()
        pendingBursts.removeAll()
        lastBurstAt.removeAll()
        combo.reset()
        golden = nil
        activeOrder = nil
        state.activeContract = Contracts.unchosenID
        save()
        return state.legacy.level
    }

    // MARK: Legacy tree

    /// Non-nil while the player has more Legacy levels than perk picks - each level owes
    /// exactly one pick, presented like a perk choice. Derived, so a relaunch mid-choice
    /// (or a pre-tree save with existing levels) simply re-offers.
    var pendingLegacyPerkOffer: [LegacyPerk]? {
        let owed = state.legacy.level - state.legacyPerks.values.reduce(0, +)
        guard owed > 0 else { return nil }
        let offer = LegacyTree.offer(level: state.legacy.level, taken: state.legacyPerks)
        return offer.isEmpty ? nil : offer
    }

    func chooseLegacyPerk(_ id: String) {
        guard pendingLegacyPerkOffer?.contains(where: { $0.id == id }) == true else { return }
        state.legacyPerks[id, default: 0] += 1
        save()
    }

    // MARK: Research

    func researchRank(_ id: String) -> Int { state.research[id] ?? 0 }

    /// What the given node costs right now, award-scaled - the one lookup every UI label
    /// and purchase path must share so the price shown is always the price paid.
    func researchCost(_ node: ResearchNode) -> Int {
        node.cost(forRank: researchRank(node.id), award: state.lastPrestigeAward)
    }

    /// How many research ranks the player could afford immediately after franchising right
    /// now - shown on the prestige confirm so the reset reads as "this buys my next
    /// breakthroughs", which is the decision actually being made. Greedy cheapest-first
    /// walk over a copy of the ranks; bounded by the tree's 90 total ranks.
    func projectedResearchRanks(afterAward award: Int, spendable: Int) -> Int {
        guard award > 0 || spendable > 0 else { return 0 }
        var ranks = state.research
        var budget = spendable
        var bought = 0
        while bought < 90 {
            let affordable = Research.nodes
                .filter { Research.canBuy($0, ranks: ranks, stars: budget, award: award) }
                .map { ($0, $0.cost(forRank: ranks[$0.id] ?? 0, award: award)) }
                .min { $0.1 < $1.1 }
            guard let (node, cost) = affordable else { break }
            budget -= cost
            ranks[node.id] = (ranks[node.id] ?? 0) + 1
            bought += 1
        }
        return bought
    }

    func canBuyResearch(_ node: ResearchNode) -> Bool {
        Research.canBuy(node, ranks: state.research, stars: state.stars,
                        award: state.lastPrestigeAward)
    }

    @discardableResult
    func buyResearch(_ node: ResearchNode, persist: Bool = true) -> Bool {
        guard canBuyResearch(node) else { return false }
        let rank = researchRank(node.id)
        state.stars -= researchCost(node)
        state.research[node.id] = rank + 1
        if persist { save() }
        return true
    }

    /// Buys the cheapest affordable rank, over and over, until nothing more fits the star
    /// balance - the same greedy cheapest-first walk `projectedResearchRanks` already uses
    /// for its preview number, but actually spending. A player with a large star surplus
    /// after several franchise resets otherwise has to tap every affordable node in every
    /// branch by hand. Returns how many ranks were bought.
    ///
    /// Saves once at the end rather than once per rank - up to 90 ranks in a single tap
    /// would otherwise be 90 synchronous full-state JSON encodes back to back.
    @discardableResult
    func buyAllAffordableResearch() -> Int {
        var bought = 0
        while bought < 90 {
            guard let node = Research.nodes
                .filter({ canBuyResearch($0) })
                .min(by: { researchCost($0) < researchCost($1) })
            else { break }
            guard buyResearch(node, persist: false) else { break }
            bought += 1
        }
        if bought > 0 { save() }
        return bought
    }

    // MARK: Quests

    private func advanceQuests(kind: QuestKind, by amount: Double) {
        guard amount > 0 else { return }
        for index in state.quests.indices where state.quests[index].kind == kind {
            state.quests[index].progress += amount
        }
        if state.weeklyQuest?.kind == kind { state.weeklyQuest?.progress += amount }
    }

    private func advanceQuests(kind: QuestKind, to value: Double) {
        for index in state.quests.indices where state.quests[index].kind == kind {
            state.quests[index].progress = Swift.max(state.quests[index].progress, value)
        }
        if state.weeklyQuest?.kind == kind {
            state.weeklyQuest?.progress = Swift.max(state.weeklyQuest?.progress ?? 0, value)
        }
    }

    var claimableQuests: Int {
        state.quests.filter(\.isComplete).count
            + ((state.weeklyQuest?.isComplete ?? false) ? 1 : 0)
    }

    // MARK: Weekly challenge

    /// One oversized quest per calendar week: a serve target sized to ~6 active-ish hours
    /// of the player's current throughput, paying 150 gems - premium-feel, weekly cadence,
    /// same claim flow as everything else. Rolls in `bootstrapSystems`/foreground so it's
    /// always current; an unfinished week simply expires.
    func rollWeeklyQuestIfNeeded() {
        // Not before the tutorial is done: rolling on first launch snapshotted a serve rate
        // of zero, handing a brand-new player the floor-sized target - live report was a
        // weekly challenge already 15% done (and claimable within the first session, 150
        // gems and all) before the player ever found the tab.
        guard state.tutorial.finished else { return }
        let week = GuestChef.weekKey(now: state.now)
        guard state.weeklyQuestWeek != week else { return }
        state.weeklyQuestWeek = week
        // ~10 online-equivalent hours of throughput (offline serves don't count toward
        // serve quests), so 150 gems asks for a real week of showing up, not a freebie.
        // The floor matters for week one, when the serve rate is still tiny: 25K serves is
        // a couple of real online hours across the week, not ten minutes of a fast fryer.
        let target = Swift.max(25_000, (state.automatedServeRate * 10 * 3600).rounded())
        state.weeklyQuest = ActiveQuest(
            id: "weekly-\(week)", kind: .serve, target: target, progress: 0,
            rewardGems: 150, rewardSeconds: 600
        )
    }

    @discardableResult
    func claimWeeklyQuest(persist: Bool = true) -> ActiveQuest? {
        guard let quest = state.weeklyQuest, quest.isComplete else { return nil }
        state.gems += quest.rewardGems
        addCoins(Swift.max(1_000, state.automatedRate * quest.rewardSeconds))
        state.weeklyQuest = nil // done for the week; next Monday rolls a fresh one
        if persist { save() }
        return quest
    }

    /// One tap collects every finished thing at once: completed quests, the weekly
    /// challenge, returned errands, and a filled catering order. Returns how many things
    /// were claimed - the Daily Plan's "claim everything" runs on this.
    ///
    /// Every sub-claim skips its own `save()` and this saves once at the end - `save()` does
    /// a synchronous full-state JSON encode plus an atomic disk write, so a late-game player
    /// with a big backlog claiming everything at once must not pay for one of those per item.
    @discardableResult
    func claimAllReady() -> Int {
        var claimed = 0
        for quest in state.quests.filter(\.isComplete) {
            if claimQuest(id: quest.id, persist: false) != nil { claimed += 1 }
        }
        if claimWeeklyQuest(persist: false) != nil { claimed += 1 }
        for errand in claimableErrands {
            if collectErrand(id: errand.id, persist: false) != nil { claimed += 1 }
        }
        if claimCatering(persist: false) != nil { claimed += 1 }
        if claimed > 0 { save() }
        return claimed
    }

    /// Scoped to exactly what the Quests tab shows (regular quests, the weekly challenge,
    /// today's catering order) - not errands, which live in a different sheet entirely.
    /// `claimAllReady()` stays the "claim literally everything" version the Daily Plan uses;
    /// this is what a "Claim All" button placed inside that one sheet should actually do.
    @discardableResult
    func claimAllQuests() -> Int {
        var claimed = 0
        for quest in state.quests.filter(\.isComplete) {
            if claimQuest(id: quest.id, persist: false) != nil { claimed += 1 }
        }
        if claimWeeklyQuest(persist: false) != nil { claimed += 1 }
        if claimCatering(persist: false) != nil { claimed += 1 }
        if claimed > 0 { save() }
        return claimed
    }

    /// Scoped to errands alone, for a "Claim All" button in the Staff sheet - same reasoning
    /// as `claimAllQuests()`.
    @discardableResult
    func claimAllErrands() -> Int {
        var claimed = 0
        for errand in claimableErrands {
            if collectErrand(id: errand.id, persist: false) != nil { claimed += 1 }
        }
        if claimed > 0 { save() }
        return claimed
    }

    @discardableResult
    func claimQuest(id: String, persist: Bool = true) -> ActiveQuest? {
        guard let index = state.quests.firstIndex(where: { $0.id == id }),
              state.quests[index].isComplete else { return nil }
        let quest = state.quests[index]

        state.gems += quest.rewardGems
        let coins = Swift.max(500, state.automatedRate * quest.rewardSeconds)
        addCoins(coins)
        state.questsClaimed += 1
        awardTickets(Festival.ticketsPerQuest)

        state.quests.remove(at: index)
        Quests.refill(state: &state, incomePerSecond: state.automatedRate)
        if persist { save() }
        return quest
    }

    // MARK: Achievements

    var claimableAchievements: [AchievementSpec] {
        AchievementCatalog.all.filter {
            !state.claimedAchievements.contains($0.id) && Achievements.isComplete($0, state: state)
        }
    }

    @discardableResult
    func claimAchievement(id: String, persist: Bool = true) -> AchievementSpec? {
        guard let spec = AchievementCatalog.spec(id),
              !state.claimedAchievements.contains(id),
              Achievements.isComplete(spec, state: state) else { return nil }
        state.claimedAchievements.insert(id)
        state.gems += spec.rewardGems
        if persist { save() }
        return spec
    }

    @discardableResult
    func claimAllAchievements() -> Int {
        var claimed = 0
        for spec in claimableAchievements {
            if claimAchievement(id: spec.id, persist: false) != nil { claimed += 1 }
        }
        if claimed > 0 { save() }
        return claimed
    }

    // MARK: Manager errands

    var claimableErrands: [ActiveErrand] {
        state.errands.filter { $0.isComplete(at: state.now) }
    }

    @discardableResult
    func startErrand(managerID: String, hours: Double) -> Bool {
        guard state.errands.count < Errands.maxSlots else { return false }
        guard let manager = state.manager(id: managerID),
              state.unassignedManagers.contains(where: { $0.id == managerID }) else { return false }
        let (gems, coins) = Errands.reward(manager: manager, hours: hours,
                                           incomePerSecond: state.automatedRate)
        state.errands.append(ActiveErrand(managerID: managerID, startedAt: state.now,
                                          duration: hours * 3600, rewardGems: gems, rewardCoins: coins))
        save()
        return true
    }

    /// What an errand's coin half is worth right now - priced at the CURRENT rate, not the
    /// rate when it started. Start-time pricing was an exploit: two 12h errands launched
    /// just before a Franchise banked half a day of the old empire's income straight
    /// through the reset, dwarfing Seed Capital's carefully-capped head start. Live
    /// pricing is also the coherent story: your empire as it stands pays the contract.
    func errandCoinValue(_ errand: ActiveErrand) -> Double {
        state.automatedRate * errand.duration * 0.5
    }

    @discardableResult
    func collectErrand(id: String, persist: Bool = true) -> ActiveErrand? {
        guard let index = state.errands.firstIndex(where: { $0.id == id }),
              state.errands[index].isComplete(at: state.now) else { return nil }
        var errand = state.errands.remove(at: index)
        errand.rewardCoins = errandCoinValue(errand)
        state.gems += errand.rewardGems
        addCoins(errand.rewardCoins)
        if persist { save() }
        return errand
    }

    // MARK: Weekly Gauntlet

    /// The skill-expression mode for players who've solved the main loop: a ten-minute
    /// scored sprint on the live board, once per calendar week, under a weekly mutator.
    /// Score = coins earned in the window; the purse scales with how many multiples of
    /// your ten-minute automated baseline you beat - pure play skill (taps, combos,
    /// boosts, Rush timing) is exactly what beats the baseline.
    static let gauntletSeconds: TimeInterval = 600

    struct GauntletMutator {
        let id: String
        let title: String
        let detail: String
    }

    static let gauntletMutators: [GauntletMutator] = [
        GauntletMutator(id: "handsonly", title: "Hands Only",
                        detail: "While your combo is alive, everything pays x3 - never stop tapping."),
        GauntletMutator(id: "vipnight", title: "VIP Night",
                        detail: "Golden customers swarm - x5 spawn odds for the whole sprint."),
        GauntletMutator(id: "highstakes", title: "High Stakes",
                        detail: "Everything pays x2... but your combo decays twice as fast."),
    ]

    var gauntletMutator: GauntletMutator {
        let week = GuestChef.weekKey(now: state.now)
        return Self.gauntletMutators[((week % Self.gauntletMutators.count)
                                      + Self.gauntletMutators.count) % Self.gauntletMutators.count]
    }

    var gauntletActive: Bool {
        guard let ends = state.gauntletEndsAt else { return false }
        return ends > state.now
    }

    var gauntletPlayedThisWeek: Bool {
        state.gauntletWeekPlayed == GuestChef.weekKey(now: state.now)
    }

    @discardableResult
    func startGauntlet() -> Bool {
        // A staffed board is required: starting with rate zero pinned a baseline of 1,
        // and rebuilding mid-sprint guaranteed the maximum purse - cheese, not skill.
        guard !gauntletActive, !gauntletPlayedThisWeek, state.automatedRate > 0 else { return false }
        state.gauntletWeekPlayed = GuestChef.weekKey(now: state.now)
        state.gauntletScore = 0
        // Baseline pinned NOW: computing it at settle time let a player unstaff the board
        // just before the horn to crater the baseline and max the purse.
        state.gauntletBaseline = Swift.max(1, state.automatedRate * Self.gauntletSeconds)
        state.gauntletEndsAt = state.now.addingTimeInterval(Self.gauntletSeconds)
        save()
        return true
    }

    /// Called from the tick loop; settles the sprint the moment time expires.
    private func settleGauntletIfFinished(now: Date) {
        guard let ends = state.gauntletEndsAt, ends <= now else { return }
        state.gauntletEndsAt = nil
        let score = state.gauntletScore
        state.gauntletBestEver = Swift.max(state.gauntletBestEver, score)
        // Purse: baseline is ten idle minutes; every full multiple of it earned pays 15
        // gems, capped at 90 - an all-out sprint roughly doubles-to-triples idle, so the
        // cap needs real play to reach without being farmable.
        let baseline = Swift.max(1, state.gauntletBaseline)
        // Clamp in Double space BEFORE converting: `Int(aDoubleTooLargeToFit)` is a fatal
        // runtime trap, not a throwable error, and a late-game sprint scores far past
        // Int.max (9.2e18) - this crashed the app outright on any save that got there, and
        // was what killed the 8-hour long-horizon sim. Comparing as Doubles is always safe
        // however large the value is. The purse caps at 90 gems (6 multiples) regardless,
        // so clamping costs the player nothing.
        let multiples = Int(Swift.min(score / baseline, 1_000))
        let gems = Swift.min(90, multiples * 15)
        if gems > 0 { state.gems += gems }
        toast = "Gauntlet over! \(Format.currency(score)) earned - +\(gems) gems"
        save()
    }

    /// Gauntlet mutator hooks, read by the payout paths while a sprint runs.
    var gauntletTapBonus: Double {
        gauntletActive && gauntletMutator.id == "handsonly" ? 5 : 1
    }
    var gauntletPayoutBonus: Double {
        gauntletActive && gauntletMutator.id == "highstakes" ? 2 : 1
    }
    var gauntletGoldenBonus: Double {
        gauntletActive && gauntletMutator.id == "vipnight" ? 5 : 1
    }

    // MARK: Kitchen tools

    /// Rolls the drop table at one of the game's event moments. New finds celebrate via
    /// `pendingToolDrop`; duplicates quietly convert to gems with a toast.
    private func rollToolDrop(_ moment: Tools.DropMoment) {
        guard let tool = Tools.roll(moment: moment,
                                    roll1: Double.random(in: 0..<1, using: &rng),
                                    roll2: Double.random(in: 0..<1, using: &rng)) else { return }
        if state.tools.insert(tool.id).inserted {
            pendingToolDrop = tool
        } else {
            let gems = Tools.duplicateGems(tool.rarity)
            state.gems += gems
            toast = "Duplicate \(tool.name) - traded for \(gems) gems"
        }
    }

    // MARK: Catering

    /// One order per calendar day, rolled against the current venue. An unfinished or
    /// unclaimed order simply expires - tomorrow brings a fresh one.
    func rollCateringIfNeeded(calendar: Calendar = .current) {
        let day = calendar.ordinality(of: .day, in: .era, for: state.now) ?? 0
        // A live unfinished order keeps its full 24 hours even across midnight - the old
        // day-key-only check silently replaced an 11pm order one hour in. A resolved
        // (claimed or expired) order still only re-rolls once per calendar day.
        if let current = state.catering {
            if !current.claimed, current.expiresAt > state.now { return }
            if current.day == day { return }
        }
        state.catering = Catering.roll(day: day, state: state, now: state.now)
    }

    /// Called from the tick loop with each station's completed serves.
    private func advanceCatering(venue: Int, station: Int, served: Int) {
        guard var order = state.catering, !order.claimed,
              order.venue == venue,
              order.requirements[station] != nil,
              order.expiresAt > state.now else { return }
        let before = order.isComplete
        order.progress[station, default: 0] += served
        state.catering = order
        if !before, order.isComplete {
            toast = "Catering order filled! Collect it in Goals."
        }
    }

    @discardableResult
    func claimCatering(persist: Bool = true) -> CateringOrder? {
        guard var order = state.catering, order.isComplete, !order.claimed,
              order.expiresAt > state.now else { return nil }
        order.claimed = true
        state.catering = order
        state.gems += order.rewardGems
        addCoins(Swift.max(2_000, state.automatedRate * order.rewardIncomeSeconds))
        awardTickets(Festival.ticketsPerQuest)
        rollToolDrop(.cateringDelivered)
        if persist { save() }
        return order
    }

    // MARK: Expeditions (Food Court Face-Offs)

    var expeditionComplete: Bool {
        state.expedition?.isComplete(at: state.now) ?? false
    }

    /// Starts a Face-Off with exactly three benched managers. The outcome roll is fixed
    /// now (see ActiveExpedition.roll) - what's left is the wait.
    @discardableResult
    func startExpedition(managerIDs: [String], tierID: String) -> Bool {
        guard state.expedition == nil,
              managerIDs.count == Expeditions.crewSize,
              Set(managerIDs).count == Expeditions.crewSize else { return false }
        let benchIDs = Set(state.unassignedManagers.map(\.id))
        guard managerIDs.allSatisfy(benchIDs.contains) else { return false }
        let tier = Expeditions.tier(tierID)
        state.expedition = ActiveExpedition(
            managerIDs: managerIDs, startedAt: state.now,
            duration: tier.hours * 3600, tier: tierID,
            roll: Double.random(in: 0..<1, using: &rng))
        save()
        return true
    }

    /// Resolves a finished Face-Off: win pays the tier's purse (and sometimes a recruit),
    /// a loss still pays a consolation quarter - the time was real either way.
    @discardableResult
    func resolveExpedition() -> (won: Bool, gems: Int, coins: Double, recruit: ManagerSpec?)? {
        guard let expedition = state.expedition,
              expedition.isComplete(at: state.now) else { return nil }
        let tier = Expeditions.tier(expedition.tier)
        let won = Expeditions.isWin(expedition, managers: state.managers)
        state.expedition = nil

        let gems = won ? tier.rewardGems : tier.rewardGems / 4
        let coins = Swift.max(1_000, state.automatedRate * tier.rewardIncomeHours * 3600)
            * (won ? 1 : 0.25)
        state.gems += gems
        addCoins(coins)
        var recruit: ManagerSpec?
        if won {
            state.expeditionWins += 1
            if Double.random(in: 0..<1, using: &rng) < tier.recruitChance {
                recruit = grantManager(rarity: .epic)
            }
            rollToolDrop(.expeditionWin)
        }
        toast = won
            ? "Face-Off won! +\(gems) gems\(recruit.map { " · \($0.name) joins!" } ?? "")"
            : "Face-Off lost - the crew still learned something. +\(gems) gems"
        save()
        return (won, gems, coins, recruit)
    }

    // MARK: Festival

    func awardTickets(_ amount: Int) {
        guard amount > 0 else { return }
        Festival.rolloverIfNeeded(&state.festival, now: state.now)
        state.festival.tickets += amount
    }

    /// True when premium rewards are claimable: a bought pass, or VIP which includes it.
    var festivalPremiumActive: Bool {
        state.festival.premiumUnlocked || state.entitlements.includesFestivalPremium
    }

    func claimFestival(tier: Int, premium: Bool, persist: Bool = true) -> FestivalReward? {
        guard Festival.canClaim(state.festival, tier: tier, premium: premium,
                                premiumActive: festivalPremiumActive) else { return nil }
        let reward = premium ? Festival.tier(tier).premium : Festival.tier(tier).free
        if premium { state.festival.claimedPremium.append(tier) }
        else { state.festival.claimedFree.append(tier) }
        state.bestFestivalTier = Swift.max(state.bestFestivalTier, tier)
        apply(reward)
        if persist { save() }
        return reward
    }

    /// A returning player can find several tiers unlocked at once across both tracks (up to
    /// 60 individual taps otherwise, at 30 tiers x free/premium) - same "claim all" pattern
    /// as quests/errands/achievements.
    @discardableResult
    func claimAllFestival() -> Int {
        var claimed = 0
        for tier in Festival.allTiers.map(\.index) {
            if claimFestival(tier: tier, premium: false, persist: false) != nil { claimed += 1 }
            if festivalPremiumActive,
               claimFestival(tier: tier, premium: true, persist: false) != nil { claimed += 1 }
        }
        if claimed > 0 { save() }
        return claimed
    }

    private func apply(_ reward: FestivalReward) {
        switch reward {
        case .gems(let amount):
            state.gems += amount
        case .coinSeconds(let seconds):
            let seasonBonus = Festival.modifier(seasonID: state.festival.seasonID).tierCoinMultiplier
            addCoins(Swift.max(1_000, state.automatedRate * seconds) * seasonBonus)
        case .manager(let rarity):
            _ = grantManager(rarity: rarity)
        case .boost(let multiplier, let hours):
            addBoost(id: "festival", label: "Festival ×\(Format.trim(multiplier))",
                     multiplier: multiplier, hours: hours)
        }
    }

    func unlockFestivalPremium() {
        state.festival.premiumUnlocked = true
        save()
    }

    // MARK: League

    func settleLeagueIfFinished() {
        guard League.isFinished(state.league, now: state.now) else { return }
        let outcome = League.settle(state.league)
        switch outcome {
        case .promoted(_, _, _, let gems), .held(_, _, let gems):
            state.gems += gems
        case .relegated:
            break
        }
        // Legendary managers otherwise only come from a paid Carnival Pass / VIP reaching
        // festival tier 30 - topping the whole ladder is the one purely free route to the
        // top rarity. Deliberately rare (#1 in the hardest tier), so it never undercuts the
        // paid path's convenience, but a dedicated free player is never permanently locked out.
        if case .held(let tier, let rank, _) = outcome, tier == .diamond, rank == 1 {
            let spec = grantManager(rarity: .legendary)
            toast = "Diamond Champion! \(spec.name) joins your roster"
        }
        let nextTier = League.nextTier(after: outcome, current: state.league.tier)
        if nextTier.rawValue > state.bestLeagueTierReached.rawValue {
            state.bestLeagueTierReached = nextTier
        }
        state.league = League.newWeek(tier: nextTier,
                                      now: state.now,
                                      seasonsPlayed: state.league.seasonsPlayed + 1,
                                      nemesisSeed: state.nemesisSeed)
        pendingLeagueOutcome = outcome
        save()
    }

    // MARK: Currency & effects

    func addCoins(_ amount: Double) {
        guard amount > 0 else { return }
        state.coins += amount
        recordEarnings(amount)
    }

    func addGems(_ amount: Int) {
        guard amount > 0 else { return }
        state.gems += amount
    }

    @discardableResult
    func spendGems(_ amount: Int) -> Bool {
        guard state.gems >= amount else { return false }
        state.gems -= amount
        return true
    }

    func addBoost(id: String, label: String, multiplier: Double, hours: Double) {
        Boosts.add(Boosts.make(id: id, label: label, multiplier: multiplier, hours: hours, from: state.now), to: &state)
    }

    func setEntitlement(vip: Bool? = nil, starterPack: Bool? = nil,
                        grandOpeningBundle: Bool? = nil, mogul: Bool? = nil,
                        foundersBundle: Bool? = nil) {
        if let vip { state.entitlements.vip = vip }
        if let starterPack { state.entitlements.starterPack = starterPack }
        if let grandOpeningBundle { state.entitlements.grandOpeningBundle = grandOpeningBundle }
        if let mogul { state.entitlements.mogul = mogul }
        if let foundersBundle { state.entitlements.foundersBundle = foundersBundle }
    }

    @discardableResult
    func timeWarp(hours: Double) -> Double {
        let amount = state.automatedRate * hours * 3600
        addCoins(amount)
        return amount
    }

    @discardableResult
    func instantCompleteAll() -> Double {
        let venue = Balance.venue(state.currentVenue)
        let multiplier = payoutMultiplier
        var total: Double = 0
        var served = 0
        for spec in venue.stations {
            var station = state.venues[venue.id].stations[spec.id]
            guard station.isOwned else { continue }
            let payout = state.baseRevenue(venue: venue.id, station: spec.id) * multiplier
            total += payout
            served += 1
            station.elapsed = 0
            if !station.isStaffed { station.isRunning = false }
            state.venues[venue.id].stations[spec.id] = station
            lastServe[spec.id] = ServeEvent(station: spec.id, amount: payout, count: 1)
        }
        servedCustomers += served
        registerServed(served)
        addCoins(total)
        return total
    }

    /// Grants managers on every currently owned station in a venue. Always premium - the only
    /// callers are the "Automate Venue" gem sink and the Grand Opening Bundle / Franchise
    /// Accelerator IAPs, never a coin hire.
    func grantManagerPack(venue id: Int = 0) {
        for spec in Balance.venue(id).stations {
            let station = state.venues[id].stations[spec.id]
            if station.isOwned && !station.isStaffed {
                state.hire(specID: ManagerCatalog.traineeID, venue: id, station: spec.id, premium: true)
            }
        }
        advanceQuests(kind: .hire, to: Double(state.assignedManagerCount))
    }

    /// True when a venue has at least one owned station still waiting on a manager - what
    /// the "Automate Venue" gem sink and the Franchise Accelerator both check before selling
    /// something that would do nothing.
    func hasUnstaffedStation(venue id: Int) -> Bool {
        Balance.venue(id).stations.contains { spec in
            let station = state.venues[id].stations[spec.id]
            return station.isOwned && !station.isStaffed
        }
    }

    /// The whale bundle: a lump of gems, a chunk of banked income, and a long boost. Priced
    /// as a mid-tier "get ahead fast" purchase between the Starter Pack and VIP.
    @discardableResult
    func grantFranchiseAccelerator() -> Double {
        addGems(2_500)
        let earned = timeWarp(hours: 8)
        addBoost(id: "accelerator", label: "Accelerator ×2", multiplier: 2, hours: 48)
        return earned
    }

    /// The one-time anchor purchase. Unlike the Starter Pack (venue 0 only, most useful to a
    /// brand new player), this automates every station in every venue the player has already
    /// opened - so it stays a genuinely good deal no matter how far along they are when they
    /// buy it, rather than losing value the moment they've moved past venue 0.
    func grantGrandOpeningBundle() {
        addGems(1_500)
        for venue in Balance.venues where state.venues[venue.id].unlocked {
            grantManagerPack(venue: venue.id)
        }
        addBoost(id: "grand-opening", label: "Grand Opening ×2", multiplier: 2, hours: 72)
    }

    /// Adds spendable-only stars: usable on research immediately, but never added to
    /// `lifetimeStars`. The permanent profit multiplier stays something only a real Franchise
    /// reset can grow - this lets a purchase (gems or real money) shorten the research grind
    /// without ever letting it buy the core prestige decision itself.
    func grantResearchStars(_ amount: Int) {
        guard amount > 0 else { return }
        state.stars += amount
        save()
    }

    /// The gem sink's star payout: 15% of the latest Franchise award, floored at the old
    /// flat 300. Both purchases scale with the award for the same reason research prices do
    /// (`Balance.researchAwardCostFraction`) - a flat grant is meaningless one board after
    /// week one. 15% ≈ a third of one deep rank; the paid Grant below is the serious one.
    var researchBoostStars: Int {
        Swift.max(300, Int(0.15 * Double(state.lastPrestigeAward)))
    }

    /// The $9.99 Research Grant's payout: 60% of the latest award, floored at 2,500 -
    /// about a rank and a half of deep research whenever it's bought, forever.
    var researchGrantStars: Int {
        Swift.max(2_500, Int(0.6 * Double(state.lastPrestigeAward)))
    }

    // MARK: Free boost (Coffee Break)

    var boostReady: Bool { state.now >= state.boostAvailableAt }

    var boostCooldownRemaining: TimeInterval {
        Swift.max(0, state.boostAvailableAt.timeIntervalSince(state.now))
    }

    /// The game has no ads, so this is simply given away on a cooldown.
    @discardableResult
    func claimFreeBoost() -> Bool {
        guard boostReady else { return false }
        addBoost(id: ActivePlay.freeBoostID,
                 label: "Coffee Break ×\(Format.trim(ActivePlay.freeBoostMultiplier))",
                 multiplier: ActivePlay.freeBoostMultiplier,
                 hours: ActivePlay.freeBoostHours)
        // The cooldown starts when the boost ENDS, not when it's claimed - Rush Hour
        // already worked this way (rushAvailableAt is set from rushEndsAt); this matched
        // it, so the 15-minute active window is real bonus time on top of the 30-minute
        // cooldown, not eaten by it.
        state.boostAvailableAt = state.now
            .addingTimeInterval(ActivePlay.freeBoostHours * 3600)
            .addingTimeInterval(ActivePlay.freeBoostCooldownMinutes * 60)
        state.tutorial.complete(.coffeeBreak)
        save()
        return true
    }

    // MARK: Welcome-back double

    /// Doubling the offline payout is free, once a day. It used to be behind a rewarded ad.
    func offlineDoubleAvailable(calendar: Calendar = .current) -> Bool {
        guard let last = state.lastOfflineDoubleDay else { return true }
        return calendar.startOfDay(for: state.now) > calendar.startOfDay(for: last)
    }

    @discardableResult
    func claimOfflineDouble(_ report: OfflineReport, calendar: Calendar = .current) -> Bool {
        guard offlineDoubleAvailable(calendar: calendar) else { return false }
        state.lastOfflineDoubleDay = calendar.startOfDay(for: state.now)
        addCoins(report.coins)
        save()
        return true
    }

    /// Price to double a welcome-back payout with gems once the free daily double is already
    /// spent - previously there was no way to double at all in that case, which left the
    /// screen showing only "No thanks, collect" with nothing to have said no to.
    static let offlineDoubleGemCost = 40

    /// Doesn't touch `lastOfflineDoubleDay` - that flag gates the free path only, and this
    /// one exists specifically for when the free path is already used today.
    @discardableResult
    func claimOfflineDoubleWithGems(_ report: OfflineReport) -> Bool {
        guard spendGems(GameEngine.offlineDoubleGemCost) else { return false }
        addCoins(report.coins)
        save()
        return true
    }

    // MARK: Daily rewards

    var dailyStatus: DailyClaimStatus { DailyRewards.status(state: state, now: state.now) }

    var dailyAvailable: Bool {
        if case .available = dailyStatus { return true }
        return false
    }

    @discardableResult
    func claimDaily() -> DailyRewards.Payout? {
        let payout = DailyRewards.claim(state: &state, now: state.now)
        if let payout {
            // Through addCoins, not state.coins directly, so the reward counts toward the
            // league and earn-quests like every other grant - claim() leaves coins to us.
            if payout.coins > 0 { addCoins(payout.coins) }
            awardTickets(Festival.ticketsPerDaily)
            save()
        }
        return payout
    }

    // MARK: Login streak

    func addStreakFreeze() {
        state.daily.streakFreezes += 1
        save()
    }

    var claimableStreakMilestones: [(day: Int, gems: Int)] {
        DailyRewards.streakMilestones.filter {
            state.daily.streakLength >= $0.day && !state.daily.claimedStreakMilestones.contains($0.day)
        }
    }

    @discardableResult
    func claimStreakMilestone(day: Int) -> Int? {
        guard let milestone = DailyRewards.streakMilestones.first(where: { $0.day == day }),
              state.daily.streakLength >= day,
              !state.daily.claimedStreakMilestones.contains(day) else { return nil }
        state.daily.claimedStreakMilestones.insert(day)
        state.gems += milestone.gems
        save()
        return milestone.gems
    }

    // MARK: Tutorial

    func completeTutorialStep(_ step: TutorialStep) {
        state.tutorial.complete(step)
    }

    func skipTutorial() {
        state.tutorial.skip()
        save()
    }

    func restartTutorial() {
        state.tutorial.restart()
        save()
    }

    // MARK: Onboarding explainers

    // Pacing gates: a system's card (and its explainer) only appears once the player can
    // meaningfully touch it. Before these, a day-one player opening the Staff tab met four
    // stacked explainers describing systems that wouldn't matter for weeks - systems
    // unfurling with progress IS the onboarding pacing.

    /// Crews matter once the roster holds at least two NAMED managers (trainees can't
    /// form crews, so a wall of coin-hires shouldn't summon the crew board).
    var crewsRelevant: Bool {
        state.managers.filter { $0.specID != ManagerCatalog.traineeID }.count >= 2
    }

    /// Face-Offs need a fieldable crew: three benchable managers beyond a skeleton staff,
    /// or a veteran (any prestige) who can plan around pulling staff.
    var faceOffsRelevant: Bool {
        state.prestigeCount >= 1 || state.managers.count >= 5
    }

    /// The Gauntlet is skill expression for players who've solved the base loop.
    var gauntletRelevant: Bool {
        state.prestigeCount >= 1 || state.gauntletBestEver > 0
    }

    /// The tool chase opens with the first franchise - or instantly if something already
    /// dropped (drops can technically fire earlier via Rush).
    var toolsRelevant: Bool {
        state.prestigeCount >= 1 || !state.tools.isEmpty
    }

    /// The season-twist explainer waits until the festival itself is a thing the player
    /// has touched.
    var seasonTwistRelevant: Bool {
        state.festival.tickets > 0 || state.bestFestivalTier > 0
            || !state.festival.claimedFree.isEmpty
    }

    func hasSeenIntro(_ key: String) -> Bool { state.seenIntros.contains(key) }

    func markIntroSeen(_ key: String) {
        guard state.seenIntros.insert(key).inserted else { return }
        save()
    }

    // MARK: Debug affordances

    /// Advances the game clock only - no foreground/offline machinery, no save. Pacing
    /// simulations step this alongside `advance(by:)` so time-based gates (spawn
    /// cooldowns, combo expiry) behave as they would across real minutes of play.
    func debugAdvanceClock(seconds: TimeInterval) {
        state.timeOffset += seconds
    }

    func debugSkip(hours: Double) {
        state.timeOffset += hours * 3600
        state.lastSeen = state.now.addingTimeInterval(-hours * 3600)
        handleForeground()
        persistence.save(state)
    }

    /// Marks every open goal complete so the claim flow can be exercised on demand.
    func debugCompleteQuests() {
        for index in state.quests.indices {
            state.quests[index].progress = state.quests[index].target
        }
    }

    func debugCompleteWeeklyQuest() {
        state.weeklyQuest?.progress = state.weeklyQuest?.target ?? 0
    }

    /// Opens every venue and buys level 1 on every station - the fastest way to clear
    /// `allVenuesAndStationsUnlocked` on demand, since prestige otherwise requires it
    /// legitimately, on every run.
    func debugUnlockAllVenuesAndStations() {
        for id in Balance.venues.indices {
            state.venues[id].unlocked = true
            for stationIndex in state.venues[id].stations.indices
            where !state.venues[id].stations[stationIndex].isOwned {
                state.venues[id].stations[stationIndex].level = 1
            }
        }
    }

    func debugCompleteErrands() {
        for index in state.errands.indices {
            state.errands[index].startedAt = state.now
                .addingTimeInterval(-state.errands[index].duration - 1)
        }
    }

    func debugEndGauntlet() {
        guard state.gauntletEndsAt != nil else { return }
        state.gauntletEndsAt = state.now.addingTimeInterval(-1)
    }

    func debugCompleteExpedition() {
        guard let expedition = state.expedition else { return }
        state.expedition?.startedAt = state.now.addingTimeInterval(-expedition.duration - 1)
    }

    /// Ends the league week immediately and settles it.
    func debugEndLeagueWeek() {
        state.league.endsAt = state.now.addingTimeInterval(-1)
        settleLeagueIfFinished()
    }

    func debugReset() {
        stop()
        persistence.wipe()
        state = GameState.newGame()
        lastServe.removeAll()
        servedCustomers = 0
        combo.reset()
        golden = nil
        activeOrder = nil
        bootstrapSystems()
        start()
    }
}

/// `CACurrentMediaTime` lives in QuartzCore; wrapping it keeps the engine free of a
/// rendering-framework import and makes it trivially swappable in tests.
private func CACurrentMediaTimeCompat() -> CFTimeInterval {
    ProcessInfo.processInfo.systemUptime
}
