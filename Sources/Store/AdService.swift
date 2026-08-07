import Foundation

/// Stands in for a rewarded-ad SDK. The timing, cooldown, and reward shape all match what a
/// real integration would do, so swapping in AdMob or similar means replacing `play()` and
/// nothing else.
@MainActor
final class AdService: ObservableObject {

    static let rewardMultiplier: Double = 2
    static let rewardHours: Double = 0.25       // 15 minutes
    static let cooldownMinutes: Double = 10
    static let adDuration: TimeInterval = 5

    @Published private(set) var isPlaying = false
    @Published private(set) var secondsRemaining: Int = Int(adDuration)
    @Published var lastReward: String?

    private var task: Task<Void, Never>?

    /// VIP owners skip the wait entirely - that is a large part of what they paid for.
    func play(engine: GameEngine, reason: String = "boost", onFinish: (() -> Void)? = nil) {
        guard !isPlaying, engine.adReady else { return }

        if engine.state.entitlements.adsRemoved {
            grant(engine: engine, reason: reason)
            onFinish?()
            return
        }

        isPlaying = true
        secondsRemaining = Int(Self.adDuration)
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: Int(Self.adDuration), through: 1, by: -1) {
                self.secondsRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            self.secondsRemaining = 0
            self.isPlaying = false
            self.grant(engine: engine, reason: reason)
            onFinish?()
        }
    }

    func skip() {
        task?.cancel()
        task = nil
        isPlaying = false
    }

    private func grant(engine: GameEngine, reason: String) {
        switch reason {
        case "offline":
            // Doubling the welcome-back payout is handled by the caller, which knows the
            // amount; here we only stamp the cooldown.
            break
        default:
            engine.addBoost(
                id: "ad-boost",
                label: "×\(Format.trim(Self.rewardMultiplier)) Ad Boost",
                multiplier: Self.rewardMultiplier,
                hours: Self.rewardHours
            )
            lastReward = "×2 profit for 15 minutes"
        }
        if !engine.state.entitlements.adsRemoved {
            engine.startAdCooldown(minutes: Self.cooldownMinutes)
        }
        engine.save()
    }
}
