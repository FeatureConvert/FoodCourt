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

    func reportLifetimeEarnings(_ coins: Double) {
        guard isAuthenticated else { return }
        let score = Int(min(coins, Double(Int.max)))
        Task {
            try? await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                                 leaderboardIDs: [Leaderboard.lifetimeEarnings])
        }
    }
}
