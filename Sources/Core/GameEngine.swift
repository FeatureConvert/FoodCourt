import Foundation
import Combine

enum BuyQuantity: String, CaseIterable, Identifiable {
    case x1, x10, x100, max
    var id: String { rawValue }
    var label: String {
        switch self {
        case .x1: return "×1"
        case .x10: return "×10"
        case .x100: return "×100"
        case .max: return "MAX"
        }
    }
    var fixedAmount: Int? {
        switch self {
        case .x1: return 1
        case .x10: return 10
        case .x100: return 100
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
    @Published var buyQuantity: BuyQuantity = .x1

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
    /// Set by `prestige()` for the end-of-run recap the UI shows after the reset - the
    /// numbers have to be captured BEFORE the board wipes them.
    @Published var lastRunRecap: RunRecap?

    /// Payouts waiting to be shown, and when each station last showed one. A fast station
    /// completes ten-plus cycles a second; spawning a burst per cycle restarts the animation
    /// before it can play, so they are pooled and shown as one larger number.
    private var pendingBursts: [Int: (amount: Double, count: Int)] = [:]
    private var lastBurstAt: [Int: CFTimeInterval] = [:]
    private static let burstMinimumInterval: CFTimeInterval = 0.25

    private let persistence: GamePersisting
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
        return Double.random(in: 0..<1) < mods.doubleServeChance ? 2 : 1
    }

    /// Lifetime-earnings totals worth a one-time celebration. Every crossing is permanent
    /// (persisted in `landmarksCrossed` as the exponent), and old saves backfill silently on
    /// decode so a veteran never gets five confetti storms on update day.
    static let landmarkExponents: [Int] = [6, 9, 12, 15, 18, 21]

    private func recordEarnings(_ amount: Double) {
        let before = state.lifetimeEarnings
        state.lifetimeEarnings += amount
        state.runEarnings += amount
        state.league.score += amount
        advanceQuests(kind: .earn, by: amount)
        registerLandmarks(before: before)
    }

    private func registerLandmarks(before: Double) {
        for exponent in Self.landmarkExponents where !state.landmarksCrossed.contains(exponent) {
            let value = pow(10, Double(exponent))
            if before < value, state.lifetimeEarnings >= value {
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
            let scaled = Int((Double(tickets) * state.researchEffects.ticketMultiplier).rounded())
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
        state.globalMultiplier * comboMultiplier
            * (state.isHappyHour() ? ActivePlay.happyHourMultiplier : 1)
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

    /// How much pricier every purchase on this board is right now, purely from having gone
    /// without a reset for a while - see `Balance.stalenessMultiplier`. 1 means no tax yet.
    var costInflation: Double {
        Balance.stalenessMultiplier(
            boardAgeHours: boardAgeHours,
            graceBonusHours: (state.contract?.staleGraceDeltaHours ?? 0)
                + state.legacyEffects.staleGraceBonusHours)
    }

    func quantity(for index: Int, in venue: Int? = nil) -> Int {
        let venueID = venue ?? state.currentVenue
        let spec = Balance.venue(venueID).stations[index]
        let level = state.venues[venueID].stations[index].level
        if let fixed = buyQuantity.fixedAmount { return fixed }
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
        state.venues[venue].stations[index].level += amount

        state.tutorial.complete(.buyLevel)
        rollRecipe(venue: venue, station: index, levels: amount)
        advanceQuests(kind: .level, to: Double(Quests.highestStationLevel(state)))
        checkPerkUnlock(venue: venue, station: index)
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
        Balance.managerCost(spec: Balance.venue(state.currentVenue).stations[index]) * costInflation
    }

    @discardableResult
    func hireManager(for index: Int, free: Bool = false, premium: Bool = false) -> Bool {
        let venue = state.currentVenue
        guard state.venues[venue].stations.indices.contains(index) else { return false }
        let station = state.venues[venue].stations[index]
        guard station.isOwned, !station.isStaffed else { return false }
        let cost = managerCost(for: index)
        if !free {
            guard state.coins >= cost else { return false }
            state.coins -= cost
        }
        state.hire(specID: ManagerCatalog.traineeID, venue: venue, station: index, premium: premium)
        advanceQuests(kind: .hire, to: Double(state.assignedManagerCount))
        state.tutorial.complete(.hireManager)
        // A new save locks Coffee Break out for its first 15 minutes, so the very next
        // tutorial step would instruct the player to tap something that's visibly disabled.
        // Skip straight past it instead of ever showing a step that can't be followed.
        if state.tutorial.current == .coffeeBreak, !boostReady {
            state.tutorial.complete(.coffeeBreak)
        }
        return true
    }

    func assign(managerID: String?, venue: Int, station: Int) {
        state.assign(managerID: managerID, venue: venue, station: station)
        if managerID != nil { advanceQuests(kind: .hire, to: Double(state.assignedManagerCount)) }
    }

    /// Adds staff from a reward source and reports who turned up. Always premium - these are
    /// rare, one-off grants (festival, league, IAP), never the coin-grind staffing loop.
    @discardableResult
    func grantManager(rarity: ManagerRarity) -> ManagerSpec {
        let spec = ManagerCatalog.random(rarity: rarity, seed: Int.random(in: 0..<10_000))
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

    private func checkPerkUnlock(venue: Int, station: Int) {
        let s = state.venues[venue].stations[station]
        if Perks.pending(level: s.level, chosen: s.perks) != nil, venue == state.currentVenue {
            pendingPerkStation = station
        }
    }

    func pendingPerkLevel(venue: Int, station: Int) -> Int? {
        let s = state.venues[venue].stations[station]
        return Perks.pending(level: s.level, chosen: s.perks)
    }

    func choosePerk(venue: Int, station: Int, level: Int, index: Int) {
        state.venues[venue].stations[station].perks[level] = index
        pendingPerkStation = nil
        save()
    }

    // MARK: Recipes

    private func rollRecipe(venue: Int, station: Int, levels: Int) {
        let drop = Recipes.roll(cards: &state.recipeCards, venue: venue, station: station,
                                levelsBought: levels, random: Double.random(in: 0..<1))
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
        toast = "Rush Hour complete"
    }

    // MARK: Golden customer

    /// Called by the queue each time it rotates a customer out.
    func rollGoldenCustomer() {
        guard golden == nil, state.automatedRate > 0 || state.coins > 0 else { return }
        let chance = state.goldenChance * (state.isHappyHour() ? 2 : 1)
            * Festival.modifier(seasonID: state.festival.seasonID).goldenChanceMultiplier
        guard Double.random(in: 0..<1) < chance else { return }
        golden = GoldenCustomer(seed: Int.random(in: 0..<10_000),
                                expiresAt: state.now.addingTimeInterval(ActivePlay.goldenWindow),
                                isCritic: Double.random(in: 0..<1) < ActivePlay.criticChance)
    }

    private func expireGoldenIfNeeded(now: Date) {
        if let current = golden, current.expiresAt <= now { golden = nil }
    }

    /// Pays out 30-120 seconds of income for catching the VIP in time - x10 for a critic.
    @discardableResult
    func collectGolden() -> Double {
        guard let customer = golden else { return 0 }
        golden = nil
        let seconds = Double.random(in: ActivePlay.goldenMinSeconds...ActivePlay.goldenMaxSeconds)
        let base = Swift.max(state.automatedRate, 50)
        var amount = base * seconds * payoutMultiplier
        if customer.isCritic {
            amount *= ActivePlay.criticMultiplier
            toast = "VIP CRITIC! ×\(Int(ActivePlay.criticMultiplier)) tip: \(Format.currency(amount))"
        }
        addCoins(amount)
        return amount
    }

    // MARK: Customer orders

    /// Called by the queue each time it rotates a customer out, alongside rollGoldenCustomer.
    func rollStationOrder() {
        guard activeOrder == nil else { return }
        let venue = state.currentVenue
        let staffed = Balance.venue(venue).stations
            .filter { state.venues[venue].stations[$0.id].isStaffed }
            .map(\.id)
        guard !staffed.isEmpty else { return }
        guard Double.random(in: 0..<1) < ActivePlay.orderBaseChance else { return }
        let station = staffed.randomElement() ?? staffed[0]
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
        let seconds = Double.random(in: ActivePlay.orderBonusMinSeconds...ActivePlay.orderBonusMaxSeconds)
        let base = Swift.max(state.automatedRate, 50)
        addCoins(base * seconds * payoutMultiplier)
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

    var canPrestige: Bool {
        pendingStars > 0 && state.lifetimeEarnings >= Balance.minimumLifetimeForPrestige
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
        state.activeContract = nil
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
        guard state.prestigeCount > 0, state.activeContract == nil else { return nil }
        return Contracts.offer(prestigeCount: state.prestigeCount)
    }

    func chooseContract(_ id: String) {
        guard state.activeContract == nil,
              pendingContractOffer?.contains(where: { $0.id == id }) == true else { return }
        state.activeContract = id
        save()
    }

    // MARK: Legacy (second prestige layer)

    var canLegacyReset: Bool {
        state.prestigeCount >= Balance.legacyUnlockPrestigeCount
    }

    /// Trades away the accumulated star multiplier for a permanently bigger one. Unlike
    /// `prestige()`, this also clears stars/lifetimeStars/research AND `lifetimeEarnings` -
    /// the very things regular prestige is careful to keep - since giving those up is the
    /// entire point. Earnings must go too: stars are computed from lifetime earnings, so
    /// leaving them meant one quick re-prestige restored the entire multiplier for free
    /// and the only real cost was research - not the trade the copy promised. The star
    /// climb genuinely restarts now, which is why `Balance.legacyMultiplier` pays +20% per
    /// level instead of the +5% priced for the old, nearly-free version. Managers, recipes,
    /// achievements, errands, festival and league are left untouched: they are collections
    /// and accomplishments, not run progress.
    @discardableResult
    func legacyReset() -> Int {
        guard canLegacyReset else { return state.legacy.level }
        state.legacy.level += 1
        state.coins = 0
        state.runEarnings = 0
        state.lifetimeEarnings = 0
        state.stars = 0
        state.lifetimeStars = 0
        state.lastPrestigeAward = 0
        state.research = [:]
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        state.venues[0].stations[0].level = 1
        state.currentVenue = 0
        state.boardStartedAt = state.now
        lastServe.removeAll()
        pendingBursts.removeAll()
        lastBurstAt.removeAll()
        combo.reset()
        golden = nil
        activeOrder = nil
        state.activeContract = nil
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
    func buyResearch(_ node: ResearchNode) -> Bool {
        guard canBuyResearch(node) else { return false }
        let rank = researchRank(node.id)
        state.stars -= researchCost(node)
        state.research[node.id] = rank + 1
        save()
        return true
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
        let week = GuestChef.weekKey(now: state.now)
        guard state.weeklyQuestWeek != week else { return }
        state.weeklyQuestWeek = week
        let target = Swift.max(2_000, (state.automatedServeRate * 6 * 3600).rounded())
        state.weeklyQuest = ActiveQuest(
            id: "weekly-\(week)", kind: .serve, target: target, progress: 0,
            rewardGems: 150, rewardSeconds: 600
        )
    }

    @discardableResult
    func claimWeeklyQuest() -> ActiveQuest? {
        guard let quest = state.weeklyQuest, quest.isComplete else { return nil }
        state.gems += quest.rewardGems
        addCoins(Swift.max(1_000, state.automatedRate * quest.rewardSeconds))
        state.weeklyQuest = nil // done for the week; next Monday rolls a fresh one
        save()
        return quest
    }

    @discardableResult
    func claimQuest(id: String) -> ActiveQuest? {
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
        save()
        return quest
    }

    // MARK: Achievements

    var claimableAchievements: [AchievementSpec] {
        AchievementCatalog.all.filter {
            !state.claimedAchievements.contains($0.id) && Achievements.isComplete($0, state: state)
        }
    }

    @discardableResult
    func claimAchievement(id: String) -> AchievementSpec? {
        guard let spec = AchievementCatalog.spec(id),
              !state.claimedAchievements.contains(id),
              Achievements.isComplete(spec, state: state) else { return nil }
        state.claimedAchievements.insert(id)
        state.gems += spec.rewardGems
        save()
        return spec
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

    @discardableResult
    func collectErrand(id: String) -> ActiveErrand? {
        guard let index = state.errands.firstIndex(where: { $0.id == id }),
              state.errands[index].isComplete(at: state.now) else { return nil }
        let errand = state.errands.remove(at: index)
        state.gems += errand.rewardGems
        addCoins(errand.rewardCoins)
        save()
        return errand
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

    func claimFestival(tier: Int, premium: Bool) -> FestivalReward? {
        guard Festival.canClaim(state.festival, tier: tier, premium: premium,
                                premiumActive: festivalPremiumActive) else { return nil }
        let reward = premium ? Festival.tier(tier).premium : Festival.tier(tier).free
        if premium { state.festival.claimedPremium.append(tier) }
        else { state.festival.claimedFree.append(tier) }
        state.bestFestivalTier = Swift.max(state.bestFestivalTier, tier)
        apply(reward)
        save()
        return reward
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
        state.boostAvailableAt = state.now
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

    func hasSeenIntro(_ key: String) -> Bool { state.seenIntros.contains(key) }

    func markIntroSeen(_ key: String) {
        guard state.seenIntros.insert(key).inserted else { return }
        save()
    }

    // MARK: Debug affordances

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
