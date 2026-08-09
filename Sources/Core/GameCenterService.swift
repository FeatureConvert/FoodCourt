import Foundation
import GameKit

/// Game Center is bonus flavor, never gating - authentication happens silently at launch and
/// nothing in the app behaves differently if it fails or the player declines.
@MainActor
final class GameCenterService: ObservableObject {

    enum Leaderboard {
        static let lifetimeEarnings = "com.fable.foodcourt.leaderboard.lifetimeEarnings"
    }

    @Published private(set) var isAuthenticated = false

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            Task { @MainActor in
                self?.isAuthenticated = error == nil && GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    /// Pure and separately testable because the naive version of this clamp is a crash:
    /// `Double(Int.max)` rounds UP to 2^63 exactly, which is one past what `Int` can hold,
    /// so `Int(min(coins, Double(Int.max)))` still traps for any save whose lifetime
    /// earnings reach ~9.2e18 - the same fatal-conversion class as the star-count incident
    /// `Balance.maxSaneLifetimeStars` documents. 9.2e18 is safely below the boundary.
    nonisolated static func leaderboardScore(lifetimeEarnings: Double) -> Int {
        guard lifetimeEarnings.isFinite, lifetimeEarnings > 0 else { return 0 }
        return Int(min(lifetimeEarnings, 9.2e18))
    }

    func reportLifetimeEarnings(_ coins: Double) {
        guard isAuthenticated else { return }
        let score = Self.leaderboardScore(lifetimeEarnings: coins)
        Task {
            try? await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                                 leaderboardIDs: [Leaderboard.lifetimeEarnings])
        }
    }
}
