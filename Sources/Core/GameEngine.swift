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

@MainActor
final class GameEngine: ObservableObject {

    @Published private(set) var state: GameState
    /// Latest payout per station in the *current* venue, consumed by the card animations.
    @Published private(set) var lastServe: [Int: ServeEvent] = [:]
    /// Monotonic counter the customer queue watches to retire a waiting customer.
    @Published private(set) var servedCustomers: Int = 0
    @Published var buyQuantity: BuyQuantity = .x1

    /// Set when a session starts with meaningful offline income to report.
    @Published var pendingOfflineReport: OfflineReport?

    private let persistence: GamePersisting
    private var tickTimer: Timer?
    private var autosaveTimer: Timer?
    private var lastTickTime: CFTimeInterval = CACurrentMediaTimeCompat()

    // MARK: Lifecycle

    /// Tests pass `EphemeralPersistence` so they never write to the real save file - they
    /// run inside the app as their test host and would otherwise clobber it.
    init(state: GameState? = nil,
         startTimers: Bool = true,
         persistence: GamePersisting = DiskPersistence()) {
        self.persistence = persistence
        self.state = state ?? persistence.load()
        self.state.reconcileWithCatalog()
        Boosts.prune(&self.state)
        if startTimers { start() }
    }

    func start() {
        guard tickTimer == nil else { return }
        lastTickTime = CACurrentMediaTimeCompat()

        // 20Hz is smooth enough for the progress rings without re-rendering the tree
        // as fast as the display refreshes.
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

    /// Called when the app comes back to the foreground. Returns the offline report, if any,
    /// and credits it immediately - the sheet is a celebration, not a gate.
    func handleForeground() {
        Boosts.prune(&state)
        if let report = OfflineEarnings.compute(state: state, now: state.now) {
            state.coins += report.coins
            state.lifetimeEarnings += report.coins
            state.runEarnings += report.coins
            pendingOfflineReport = report
        }
        state.lastSeen = state.now
        lastTickTime = CACurrentMediaTimeCompat()
    }

    func handleBackground() {
        save()
    }

    // MARK: Tick

    private func step() {
        let now = CACurrentMediaTimeCompat()
        var delta = now - lastTickTime
        lastTickTime = now
        // A long stall (debugger pause, app switch) should not dump a huge payout in one
        // frame; offline earnings already covers real absences.
        delta = min(max(delta, 0), 1.0)
        guard delta > 0 else { return }

        advance(by: delta)
    }

    /// Exposed for tests and the debug time-warp.
    func advance(by delta: TimeInterval) {
        var serves: [Int: ServeEvent] = [:]
        var totalServed = 0
        let multiplier = state.globalMultiplier
        var earned: Double = 0

        for venue in Balance.venues where state.venues[venue.id].unlocked {
            for spec in venue.stations {
                var station = state.venues[venue.id].stations[spec.id]
                guard station.isOwned else { continue }

                let cycle = Balance.cycleTime(spec: spec, level: station.level)
                let revenue = Balance.revenuePerCycle(spec: spec, level: station.level) * multiplier

                if station.hasManager {
                    station.isRunning = true
                    station.elapsed += delta
                    // Closed-form rather than a loop: a maxed station can complete dozens
                    // of cycles inside a single 50ms tick.
                    let completions = floor(station.elapsed / cycle)
                    if completions > 0 {
                        station.elapsed -= completions * cycle
                        let payout = revenue * completions
                        earned += payout
                        if venue.id == state.currentVenue {
                            serves[spec.id] = ServeEvent(station: spec.id, amount: payout, count: Int(completions))
                            totalServed += Int(completions)
                        }
                    }
                } else if station.isRunning {
                    station.elapsed += delta
                    if station.elapsed >= cycle {
                        station.elapsed = 0
                        station.isRunning = false
                        earned += revenue
                        if venue.id == state.currentVenue {
                            serves[spec.id] = ServeEvent(station: spec.id, amount: revenue, count: 1)
                            totalServed += 1
                        }
                    }
                }

                state.venues[venue.id].stations[spec.id] = station
            }
        }

        if earned > 0 {
            state.coins += earned
            state.lifetimeEarnings += earned
            state.runEarnings += earned
        }
        if !serves.isEmpty {
            for (key, value) in serves { lastServe[key] = value }
            servedCustomers += totalServed
        }
    }

    // MARK: Player actions

    /// Manual tap on a station. Managed stations ignore taps - they are already running.
    @discardableResult
    func tap(station index: Int) -> Bool {
        let venue = state.currentVenue
        guard state.venues[venue].stations.indices.contains(index) else { return false }
        var station = state.venues[venue].stations[index]
        guard station.isOwned, !station.hasManager, !station.isRunning else { return false }
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
        return max(1, Balance.maxAffordable(spec: spec, level: level, coins: state.coins))
    }

    func price(for index: Int, in venue: Int? = nil) -> Double {
        let venueID = venue ?? state.currentVenue
        let spec = Balance.venue(venueID).stations[index]
        let level = state.venues[venueID].stations[index].level
        return Balance.cost(spec: spec, level: level, quantity: quantity(for: index, in: venueID))
    }

    func canAfford(index: Int) -> Bool {
        state.coins >= price(for: index)
    }

    @discardableResult
    func buy(station index: Int) -> Bool {
        let venue = state.currentVenue
        let amount = quantity(for: index)
        let cost = price(for: index)
        guard amount > 0, state.coins >= cost else { return false }
        state.coins -= cost
        state.venues[venue].stations[index].level += amount
        return true
    }

    func managerCost(for index: Int) -> Double {
        Balance.managerCost(spec: Balance.venue(state.currentVenue).stations[index])
    }

    @discardableResult
    func hireManager(for index: Int, free: Bool = false) -> Bool {
        let venue = state.currentVenue
        var station = state.venues[venue].stations[index]
        guard station.isOwned, !station.hasManager else { return false }
        let cost = managerCost(for: index)
        if !free {
            guard state.coins >= cost else { return false }
            state.coins -= cost
        }
        station.hasManager = true
        station.isRunning = true
        state.venues[venue].stations[index] = station
        return true
    }

    // MARK: Venues

    var nextLockedVenue: VenueSpec? {
        Balance.venues.first { !state.venues[$0.id].unlocked }
    }

    func canUnlock(_ venue: VenueSpec) -> Bool {
        state.coins >= venue.unlockCost
    }

    @discardableResult
    func unlock(_ venue: VenueSpec) -> Bool {
        guard !state.venues[venue.id].unlocked, canUnlock(venue) else { return false }
        state.coins -= venue.unlockCost
        state.venues[venue.id].unlocked = true
        // Hand over a working first station so the new venue is immediately playable.
        state.venues[venue.id].stations[0].level = 1
        switchTo(venue: venue.id)
        return true
    }

    func switchTo(venue id: Int) {
        guard state.venues.indices.contains(id), state.venues[id].unlocked else { return }
        state.currentVenue = id
        lastServe.removeAll()
    }

    // MARK: Income readouts

    var incomePerSecond: Double {
        var total: Double = 0
        for venue in Balance.venues where state.venues[venue.id].unlocked {
            for spec in venue.stations {
                let station = state.venues[venue.id].stations[spec.id]
                guard station.isOwned, station.hasManager else { continue }
                total += Balance.revenuePerCycle(spec: spec, level: station.level)
                    / Balance.cycleTime(spec: spec, level: station.level)
            }
        }
        return total * state.globalMultiplier
    }

    // MARK: Prestige

    var pendingStars: Int {
        Balance.pendingStars(lifetimeEarnings: state.lifetimeEarnings, currentStars: state.stars)
    }

    var canPrestige: Bool {
        pendingStars > 0 && state.lifetimeEarnings >= Balance.minimumLifetimeForPrestige
    }

    @discardableResult
    func prestige() -> Int {
        let award = pendingStars
        guard canPrestige else { return 0 }

        state.stars += award
        state.coins = 0
        state.runEarnings = 0
        // Lifetime earnings survive on purpose: stars are derived from it, so wiping it
        // would claw back the multiplier the player just earned.
        state.venues = Balance.venues.map { VenueState.fresh(venue: $0, unlocked: $0.id == 0) }
        state.venues[0].stations[0].level = 1
        state.currentVenue = 0
        lastServe.removeAll()
        save()
        return award
    }

    // MARK: Currency & effects (used by the store and gem sinks)

    func addCoins(_ amount: Double) {
        guard amount > 0 else { return }
        state.coins += amount
        state.lifetimeEarnings += amount
        state.runEarnings += amount
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

    func setEntitlement(vip: Bool? = nil, starterPack: Bool? = nil) {
        if let vip { state.entitlements.vip = vip }
        if let starterPack { state.entitlements.starterPack = starterPack }
    }

    /// Credits `hours` of automated income at full rate - what a time-warp purchase buys.
    @discardableResult
    func timeWarp(hours: Double) -> Double {
        let amount = OfflineEarnings.automatedIncomePerSecond(state) * hours * 3600
        addCoins(amount)
        return amount
    }

    /// Instantly completes one cycle on every owned station in the current venue.
    @discardableResult
    func instantCompleteAll() -> Double {
        let venue = Balance.venue(state.currentVenue)
        let multiplier = state.globalMultiplier
        var total: Double = 0
        var served = 0
        for spec in venue.stations {
            var station = state.venues[venue.id].stations[spec.id]
            guard station.isOwned else { continue }
            let payout = Balance.revenuePerCycle(spec: spec, level: station.level) * multiplier
            total += payout
            served += 1
            station.elapsed = 0
            if !station.hasManager { station.isRunning = false }
            state.venues[venue.id].stations[spec.id] = station
            lastServe[spec.id] = ServeEvent(station: spec.id, amount: payout, count: 1)
        }
        servedCustomers += served
        addCoins(total)
        return total
    }

    /// Grants managers on every currently owned station in the first venue.
    func grantManagerPack(venue id: Int = 0) {
        for spec in Balance.venue(id).stations {
            if state.venues[id].stations[spec.id].isOwned {
                state.venues[id].stations[spec.id].hasManager = true
                state.venues[id].stations[spec.id].isRunning = true
            }
        }
    }

    // MARK: Ads

    var adReady: Bool {
        state.entitlements.adsRemoved || state.now >= state.adAvailableAt
    }

    var adCooldownRemaining: TimeInterval {
        max(0, state.adAvailableAt.timeIntervalSince(state.now))
    }

    func startAdCooldown(minutes: Double) {
        state.adAvailableAt = state.now.addingTimeInterval(minutes * 60)
    }

    // MARK: Daily rewards

    var dailyStatus: DailyClaimStatus {
        DailyRewards.status(state: state, now: state.now)
    }

    var dailyAvailable: Bool {
        if case .available = dailyStatus { return true }
        return false
    }

    @discardableResult
    func claimDaily() -> DailyRewards.Payout? {
        let payout = DailyRewards.claim(state: &state, now: state.now)
        if payout != nil { save() }
        return payout
    }

    // MARK: Debug affordances

    func debugSkip(hours: Double) {
        state.timeOffset += hours * 3600
        // Rewind lastSeen so the jump reads as time spent away, then run exactly the path a
        // real foreground transition takes. Doing it here rather than waiting for a relaunch
        // matters: the 5s autosave would otherwise stamp lastSeen at the new time and erase
        // the window before the app could be reopened.
        state.lastSeen = state.now.addingTimeInterval(-hours * 3600)
        handleForeground()
        persistence.save(state)
    }

    func debugReset() {
        stop()
        persistence.wipe()
        state = GameState.newGame()
        lastServe.removeAll()
        servedCustomers = 0
        start()
    }
}

/// `CACurrentMediaTime` lives in QuartzCore; wrapping it keeps the engine free of a
/// rendering-framework import and makes it trivially swappable in tests.
private func CACurrentMediaTimeCompat() -> CFTimeInterval {
    ProcessInfo.processInfo.systemUptime
}
