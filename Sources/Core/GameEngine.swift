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

    /// Transient banners the UI reacts to.
    @Published var pendingPerkStation: Int?
    @Published var lastRecipeDrop: Recipes.Drop?
    @Published var pendingLeagueOutcome: LeagueOutcome?
    @Published var toast: String?

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
                                          playerRate: max(state.automatedRate, 1),
                                          now: state.now,
                                          seasonsPlayed: state.league.seasonsPlayed)
        }
        Festival.rolloverIfNeeded(&state.festival, now: state.now)
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
        state.lastSeen = state.now
        persistence.save(state)
    }

    // MARK: Foreground / background

    func handleForeground() {
        Boosts.prune(&state)
        if let report = OfflineEarnings.compute(state: state, now: state.now) {
            state.coins += report.coins
            recordEarnings(report.coins)
            pendingOfflineReport = report
        }
        Festival.rolloverIfNeeded(&state.festival, now: state.now)
        League.advanceRivals(&state.league, to: state.now)
        settleLeagueIfFinished()
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
        bootstrapSystems()
        save()
        start()
    }

    func pushToCloud() { cloud?.push(state) }

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
        }
        flushBursts()

        League.advanceRivals(&state.league, to: now)
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

    private func recordEarnings(_ amount: Double) {
        state.lifetimeEarnings += amount
        state.runEarnings += amount
        state.league.score += amount
        advanceQuests(kind: .earn, by: amount)
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

    /// Everything that scales a payout right now, including the transient combo.
    var payoutMultiplier: Double {
        state.globalMultiplier * comboMultiplier
    }

    var incomePerSecond: Double {
        state.automatedRate * activeBoostMultiplier * comboMultiplier
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

        var station = state.venues[venue].stations[index]
        guard station.isOwned, !station.isStaffed, !station.isRunning else { return false }
        station.isRunning = true
        station.elapsed = 0
        state.venues[venue].stations[index] = station
        return true
    }

    func quantity(for index: Int, in venue: Int? = nil) -> Int {
        let venueID = venue ?? state.currentVenue
        let spec = Balance.venue(venueID).stations[index]
        let level = state.venues[venueID].stations[index].level
        if let fixed = buyQuantity.fixedAmount { return fixed }
        return Swift.max(1, Balance.maxAffordable(spec: spec, level: level, coins: state.coins))
    }

    func price(for index: Int, in venue: Int? = nil) -> Double {
        let venueID = venue ?? state.currentVenue
        let spec = Balance.venue(venueID).stations[index]
        let level = state.venues[venueID].stations[index].level
        return Balance.cost(spec: spec, level: level, quantity: quantity(for: index, in: venueID))
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
        return true
    }

    func managerCost(for index: Int) -> Double {
        Balance.managerCost(spec: Balance.venue(state.currentVenue).stations[index])
    }

    @discardableResult
    func hireManager(for index: Int, free: Bool = false) -> Bool {
        let venue = state.currentVenue
        let station = state.venues[venue].stations[index]
        guard station.isOwned, !station.isStaffed else { return false }
        let cost = managerCost(for: index)
        if !free {
            guard state.coins >= cost else { return false }
            state.coins -= cost
        }
        state.hire(specID: ManagerCatalog.traineeID, venue: venue, station: index)
        advanceQuests(kind: .hire, to: Double(state.assignedManagerCount))
        state.tutorial.complete(.hireManager)
        return true
    }

    func assign(managerID: String?, venue: Int, station: Int) {
        state.assign(managerID: managerID, venue: venue, station: station)
        if managerID != nil { advanceQuests(kind: .hire, to: Double(state.assignedManagerCount)) }
    }

    /// Adds staff from a reward source and reports who turned up.
    @discardableResult
    func grantManager(rarity: ManagerRarity) -> ManagerSpec {
        let spec = ManagerCatalog.random(rarity: rarity, seed: Int.random(in: 0..<10_000))
        state.recruit(specID: spec.id)
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

    // MARK: Rush Hour

    var rushActive: Bool { state.isRushActive(at: state.now) }
    var rushReady: Bool { state.rushReady(at: state.now) }
    var rushRemaining: TimeInterval { state.rushRemaining(at: state.now) }
    var rushCooldownRemaining: TimeInterval { state.rushCooldownRemaining(at: state.now) }

    @discardableResult
    func startRush(force: Bool = false) -> Bool {
        guard force || rushReady else { return false }
        let now = state.now
        state.rushEndsAt = now.addingTimeInterval(state.rushDuration)
        state.rushAvailableAt = state.rushEndsAt
            .addingTimeInterval(ActivePlay.rushCooldownMinutes * 60)
        Boosts.add(BoostState(id: ActivePlay.rushBoostID, label: "Rush ×\(Format.trim(ActivePlay.rushMultiplier))",
                              multiplier: ActivePlay.rushMultiplier, expiry: state.rushEndsAt), to: &state)
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
        guard Double.random(in: 0..<1) < state.goldenChance else { return }
        golden = GoldenCustomer(seed: Int.random(in: 0..<10_000),
                                expiresAt: state.now.addingTimeInterval(ActivePlay.goldenWindow))
    }

    private func expireGoldenIfNeeded(now: Date) {
        if let current = golden, current.expiresAt <= now { golden = nil }
    }

    /// Pays out 30-120 seconds of income for catching the VIP in time.
    @discardableResult
    func collectGolden() -> Double {
        guard golden != nil else { return 0 }
        golden = nil
        let seconds = Double.random(in: ActivePlay.goldenMinSeconds...ActivePlay.goldenMaxSeconds)
        let base = Swift.max(state.automatedRate, 50)
        let amount = base * seconds * payoutMultiplier
        addCoins(amount)
        return amount
    }

    // MARK: Venues

    var nextLockedVenue: VenueSpec? {
        Balance.venues.first { !state.venues[$0.id].unlocked }
    }

    func canUnlock(_ venue: VenueSpec) -> Bool { state.coins >= venue.unlockCost }

    @discardableResult
    func unlock(_ venue: VenueSpec) -> Bool {
        guard !state.venues[venue.id].unlocked, canUnlock(venue) else { return false }
        state.coins -= venue.unlockCost
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
    }

    // MARK: Prestige

    var pendingStars: Int {
        Balance.pendingStars(lifetimeEarnings: state.lifetimeEarnings, currentStars: state.lifetimeStars)
    }

    var canPrestige: Bool {
        pendingStars > 0 && state.lifetimeEarnings >= Balance.minimumLifetimeForPrestige
    }

    @discardableResult
    func prestige() -> Int {
        let award = pendingStars
        guard canPrestige else { return 0 }

        state.stars += award            // spendable
        state.lifetimeStars += award    // permanent multiplier
        state.prestigeCount += 1
        state.coins = 0
        state.runEarnings = 0
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        state.venues[0].stations[0].level = 1
        state.currentVenue = 0
        // Staff, recipes, and research all survive a franchise reset - they are collections
        // the player built, not station upgrades. Only the board itself resets.
        lastServe.removeAll()
        pendingBursts.removeAll()
        lastBurstAt.removeAll()
        combo.reset()
        save()
        return award
    }

    // MARK: Research

    func researchRank(_ id: String) -> Int { state.research[id] ?? 0 }

    func canBuyResearch(_ node: ResearchNode) -> Bool {
        Research.canBuy(node, ranks: state.research, stars: state.stars)
    }

    @discardableResult
    func buyResearch(_ node: ResearchNode) -> Bool {
        guard canBuyResearch(node) else { return false }
        let rank = researchRank(node.id)
        state.stars -= node.cost(forRank: rank)
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
    }

    private func advanceQuests(kind: QuestKind, to value: Double) {
        for index in state.quests.indices where state.quests[index].kind == kind {
            state.quests[index].progress = Swift.max(state.quests[index].progress, value)
        }
    }

    var claimableQuests: Int { state.quests.filter(\.isComplete).count }

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
        apply(reward)
        save()
        return reward
    }

    private func apply(_ reward: FestivalReward) {
        switch reward {
        case .gems(let amount):
            state.gems += amount
        case .coinSeconds(let seconds):
            addCoins(Swift.max(1_000, state.automatedRate * seconds))
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
                                      playerRate: Swift.max(state.automatedRate, 1),
                                      now: state.now,
                                      seasonsPlayed: state.league.seasonsPlayed + 1)
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

    func setEntitlement(vip: Bool? = nil, starterPack: Bool? = nil, grandOpeningBundle: Bool? = nil) {
        if let vip { state.entitlements.vip = vip }
        if let starterPack { state.entitlements.starterPack = starterPack }
        if let grandOpeningBundle { state.entitlements.grandOpeningBundle = grandOpeningBundle }
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

    /// Grants managers on every currently owned station in a venue.
    func grantManagerPack(venue id: Int = 0) {
        for spec in Balance.venue(id).stations {
            let station = state.venues[id].stations[spec.id]
            if station.isOwned && !station.isStaffed {
                state.hire(specID: ManagerCatalog.traineeID, venue: id, station: spec.id)
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
        if payout != nil {
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
        bootstrapSystems()
        start()
    }
}

/// `CACurrentMediaTime` lives in QuartzCore; wrapping it keeps the engine free of a
/// rendering-framework import and makes it trivially swappable in tests.
private func CACurrentMediaTimeCompat() -> CFTimeInterval {
    ProcessInfo.processInfo.systemUptime
}
