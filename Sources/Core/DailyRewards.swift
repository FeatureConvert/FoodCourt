import Foundation

enum DailyRewardKind: Equatable {
    /// Paid as N hours of the player's current automated income, with a floor so a brand
    /// new account still gets a meaningful bump.
    case coins(hours: Double)
    case gems(Int)
    case boost(multiplier: Double, hours: Double)
    case grand(gems: Int, hours: Double)
}

struct DailyRewardSpec: Identifiable, Equatable {
    let day: Int
    let kind: DailyRewardKind
    var id: Int { day }

    var title: String {
        switch kind {
        case .coins(let h): return h < 1 ? "\(Int(h * 60)) min income" : "\(Format.trim(h))h income"
        case .gems(let g): return "\(g) gems"
        case .boost(let m, let h): return "×\(Format.trim(m)) for \(Format.trim(h))h"
        case .grand(let g, let h): return "\(g) gems + \(Format.trim(h))h"
        }
    }

    var isGrand: Bool { if case .grand = kind { return true }; return false }
}

enum DailyClaimStatus: Equatable {
    /// Ready to claim the given day of the calendar.
    case available(day: Int)
    /// Already claimed today; the next day unlocks after this date.
    case claimed(nextDay: Int, resetsAt: Date)
}

enum DailyRewards {

    static let calendar: [DailyRewardSpec] = [
        DailyRewardSpec(day: 1, kind: .coins(hours: 0.25)),
        DailyRewardSpec(day: 2, kind: .gems(15)),
        DailyRewardSpec(day: 3, kind: .coins(hours: 0.5)),
        DailyRewardSpec(day: 4, kind: .gems(25)),
        DailyRewardSpec(day: 5, kind: .coins(hours: 1)),
        DailyRewardSpec(day: 6, kind: .boost(multiplier: 2, hours: 1)),
        DailyRewardSpec(day: 7, kind: .grand(gems: 100, hours: 4)),
    ]

    static let cycleLength = calendar.count

    static func spec(day: Int) -> DailyRewardSpec {
        calendar[min(max(day, 1), cycleLength) - 1]
    }

    // MARK: Streak logic

    /// Streak state is derived from calendar days, not from a 24h stopwatch: a player who
    /// logs in at 11pm and again at 8am has logged in on two days, and expects credit.
    static func status(state: GameState, now: Date, calendar cal: Calendar = .current) -> DailyClaimStatus {
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)

        guard let last = state.daily.lastClaimedDay else {
            return .available(day: 1)
        }
        let lastDay = cal.startOfDay(for: last)

        if lastDay >= today {
            // Already collected today - show what is waiting tomorrow.
            let next = state.daily.currentDay > cycleLength ? 1 : state.daily.currentDay
            return .claimed(nextDay: next, resetsAt: tomorrow)
        }

        let gap = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
        if gap == 1 {
            return .available(day: min(state.daily.currentDay, cycleLength))
        }
        // Missed a day: the streak restarts from the beginning.
        return .available(day: 1)
    }

    struct Payout: Equatable {
        var coins: Double = 0
        var gems: Int = 0
        var boost: BoostState? = nil
        var day: Int = 1
    }

    /// Floor value so day 7 still feels like a prize on a young account.
    static func minimumCoins(day: Int) -> Double {
        100 * pow(5, Double(day - 1))
    }

    static func payout(for day: Int, state: GameState, now: Date) -> Payout {
        let spec = spec(day: day)
        let perSecond = OfflineEarnings.automatedIncomePerSecond(state)
        var payout = Payout(day: day)

        func coinValue(hours: Double) -> Double {
            max(minimumCoins(day: day), perSecond * hours * 3600)
        }

        switch spec.kind {
        case .coins(let hours):
            payout.coins = coinValue(hours: hours)
        case .gems(let gems):
            payout.gems = gems
        case .boost(let multiplier, let hours):
            payout.boost = BoostState(
                id: "daily-\(day)",
                label: "Daily ×\(Format.trim(multiplier))",
                multiplier: multiplier,
                expiry: now.addingTimeInterval(hours * 3600)
            )
        case .grand(let gems, let hours):
            payout.gems = gems
            payout.coins = coinValue(hours: hours)
        }
        return payout
    }

    /// Applies the reward and advances the streak. Returns nil if today is already claimed.
    @discardableResult
    static func claim(state: inout GameState, now: Date, calendar cal: Calendar = .current) -> Payout? {
        guard case .available(let day) = status(state: state, now: now, calendar: cal) else {
            return nil
        }
        let payout = payout(for: day, state: state, now: now)

        state.coins += payout.coins
        state.lifetimeEarnings += payout.coins
        state.runEarnings += payout.coins
        state.gems += payout.gems
        if let boost = payout.boost {
            Boosts.add(boost, to: &state)
        }

        updateStreak(state: &state, now: now, calendar: cal)

        state.daily.lastClaimedDay = cal.startOfDay(for: now)
        state.daily.currentDay = day >= cycleLength ? 1 : day + 1
        return payout
    }

    // MARK: Login streak

    /// (day, gems) milestones, uncapped and separate from the 7-day reward cycle - a long
    /// streak keeps paying out well past day 7 instead of just looping the same rewards.
    static let streakMilestones: [(day: Int, gems: Int)] = [
        (7, 50), (14, 100), (30, 250), (60, 500), (100, 1000),
    ]

    /// Advances or resets `streakLength` based on the same calendar-day gap `status(...)`
    /// already computed to decide the 7-day cycle. A single missed day is forgiven if a
    /// freeze is in stock; anything longer than that resets the streak to 1.
    private static func updateStreak(state: inout GameState, now: Date, calendar cal: Calendar) {
        let today = cal.startOfDay(for: now)
        guard let last = state.daily.lastClaimedDay else {
            state.daily.streakLength = 1
            return
        }
        let lastDay = cal.startOfDay(for: last)
        let gap = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0

        if gap == 1 {
            state.daily.streakLength += 1
        } else if gap == 2, state.daily.streakFreezes > 0 {
            state.daily.streakFreezes -= 1
            state.daily.streakLength += 1
        } else {
            state.daily.streakLength = 1
        }
    }
}
