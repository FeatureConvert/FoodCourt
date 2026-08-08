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

        let capFireDate = now.addingTimeInterval(state.offlineCapHours * 3600)
        plans.append(Plan(id: "offline-cap-full", title: "Offline earnings are capped",
                          body: "Come collect before you lose more.", fireDate: capFireDate))

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

        return plans
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

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.authStatus = granted ? .authorized : .denied
            }
        }
    }

    /// Cancels anything previously scheduled and re-schedules from the current state. Fixed
    /// identifiers per notification type mean a repeated call never stacks duplicates.
    func reschedule(for state: GameState, now: Date = Date()) {
        let ids = ["rush-ready", "offline-cap-full", "festival-ending", "league-ending"]
        center.removePendingNotificationRequests(withIdentifiers: ids)

        guard authStatus == .authorized else { return }

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
