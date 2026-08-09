import Foundation
import UserNotifications

/// Pure fire-date computation, kept separate from the side-effecting `UNUserNotificationCenter`
/// calls so the scheduling logic itself is unit-testable - the same split `StoreService`
/// would benefit from if StoreKit allowed it.
enum NotificationPlanner {

    struct Plan: Equatable {
        let id: String
        let title: String
        let body: String
        let fireDate: Date
    }

    /// Every notification worth scheduling, filtered to only the ones that would actually
    /// fire in the future - a fire date in the past would fire instantly, which reads as a
    /// bug the moment the app backgrounds.
    static func plan(for state: GameState, now: Date) -> [Plan] {
        var plans: [Plan] = []

        if state.rushAvailableAt > now {
            plans.append(Plan(id: "rush-ready", title: "Rush Hour is ready!",
                              body: "Tap in to start the flood.", fireDate: state.rushAvailableAt))
        }

        // Only worth saying when the player actually earns offline - a brand-new save with
        // nothing staffed used to get "come collect" with literally nothing to collect.
        // Teasing the concrete amount (what the capped stretch will have earned by the time
        // this fires) pulls much harder than a generic warning.
        let rate = state.automatedRate
        if rate > 0 {
            let capSeconds = state.offlineCapHours * 3600
            let amount = rate * capSeconds * state.offlineEfficiency * state.offlineManagerBonus
            plans.append(Plan(id: "offline-cap-full", title: "The till is full",
                              body: "Your court earned ~\(Format.currency(amount)) while you were away - earnings stall until you collect.",
                              fireDate: now.addingTimeInterval(capSeconds)))
        }

        let festivalPremiumActive = state.festival.premiumUnlocked || state.entitlements.includesFestivalPremium
        if Festival.unclaimedCount(state.festival, premiumActive: festivalPremiumActive) > 0 {
            let fireDate = state.festival.endsAt.addingTimeInterval(-2 * 3600)
            if fireDate > now {
                plans.append(Plan(id: "festival-ending", title: "Festival ends soon",
                                  body: "Claim your tier before the season resets.", fireDate: fireDate))
            }
        }

        let leagueFireDate = state.league.endsAt.addingTimeInterval(-2 * 3600)
        if leagueFireDate > now {
            plans.append(Plan(id: "league-ending", title: "League resets soon",
                              body: "Final standings lock in soon.", fireDate: leagueFireDate))
        }

        // 15 minutes before the next Happy Hour window - the appointment half of the
        // mechanic. Only for players who actually earn (same gate as the offline tease).
        if state.automatedRate > 0, let fireDate = nextHappyHourReminder(after: now) {
            plans.append(Plan(id: "happy-hour", title: "Happy Hour at \(ActivePlay.happyHourStartHour - 12)pm",
                              body: "×\(Format.trim(ActivePlay.happyHourMultiplier)) tips and double VIP odds until \(ActivePlay.happyHourEndHour - 12)pm.",
                              fireDate: fireDate))
        }

        return plans
    }

    /// The next 5:45pm local strictly after `now`.
    static func nextHappyHourReminder(after now: Date, calendar: Calendar = .current) -> Date? {
        var target = calendar.date(bySettingHour: ActivePlay.happyHourStartHour, minute: 0,
                                   second: 0, of: now).map { $0.addingTimeInterval(-15 * 60) }
        if let t = target, t <= now {
            target = calendar.date(byAdding: .day, value: 1, to: t)
        }
        return target
    }
}

/// Opt-in only, and deliberately not part of the save file - this is a device preference, not
/// game state, so it lives in `@AppStorage` rather than `GameState`. Local notifications need
/// no capability or entitlement, only the runtime permission prompt.
@MainActor
final class NotificationService: ObservableObject {

    enum AuthStatus: Equatable {
        case notDetermined, denied, authorized
    }

    @Published private(set) var authStatus: AuthStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    /// The cached `authStatus` used to start every launch at `.notDetermined` and nothing
    /// ever asked the system for the real answer - so a player who enabled notifications,
    /// killed the app, and relaunched had every `reschedule` silently no-op forever (the
    /// guard saw `.notDetermined`) until they re-toggled the setting. Read the truth on
    /// init, and have `reschedule` check the live settings rather than the cache.
    init() {
        refreshAuthStatus()
    }

    func refreshAuthStatus() {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authStatus = Self.status(from: settings.authorizationStatus)
            }
        }
    }

    private static func status(from system: UNAuthorizationStatus) -> AuthStatus {
        switch system {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.authStatus = granted ? .authorized : .denied
            }
        }
    }

    /// Cancels anything previously scheduled and re-schedules from the current state. Fixed
    /// identifiers per notification type mean a repeated call never stacks duplicates.
    /// Authorization is checked against the live system settings inside the callback, not
    /// the cached `authStatus` - see `init` for the relaunch bug the cache caused.
    func reschedule(for state: GameState, now: Date = Date()) {
        let ids = ["rush-ready", "offline-cap-full", "festival-ending", "league-ending"]
        center.removePendingNotificationRequests(withIdentifiers: ids)

        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                let status = Self.status(from: settings.authorizationStatus)
                self?.authStatus = status
                guard status == .authorized else { return }
                self?.schedule(for: state, now: now)
            }
        }
    }

    private func schedule(for state: GameState, now: Date) {
        for plan in NotificationPlanner.plan(for: state, now: now) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let interval = max(1, plan.fireDate.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
            center.add(request)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
