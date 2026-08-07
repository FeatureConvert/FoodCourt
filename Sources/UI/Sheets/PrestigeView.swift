import SwiftUI

struct PrestigeView: View {
    @EnvironmentObject private var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    let onToast: (String) -> Void

    @State private var confirming = false

    var body: some View {
        SheetScaffold(title: "Franchise Out", subtitle: "Sell up, start again, keep the multiplier") {
            VStack(spacing: 10) {
                StarIcon().frame(width: 64, height: 64)
                Text("+\(Format.count(engine.pendingStars))")
                    .font(Theme.numeric(38))
                    .foregroundStyle(Theme.star)
                Text("Franchise Stars waiting")
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .panel(Theme.panel)

            VStack(spacing: 0) {
                statRow("Stars held now", Format.count(engine.state.stars))
                divider
                statRow("Profit bonus now", "+\(Int((Balance.starMultiplier(stars: engine.state.stars) - 1) * 100))%")
                divider
                statRow("Profit bonus after", "+\(Int((Balance.starMultiplier(stars: engine.state.stars + engine.pendingStars) - 1) * 100))%",
                        highlight: engine.pendingStars > 0)
                divider
                statRow("Lifetime earnings", Format.currency(engine.state.lifetimeEarnings))
                divider
                statRow("This run", Format.currency(engine.state.runEarnings))
            }
            .panel(Theme.panel)

            VStack(alignment: .leading, spacing: 6) {
                bullet("Every station, level, and manager resets", system: "arrow.counterclockwise")
                bullet("Coins reset to zero, venues close except the first", system: "building.2.fill")
                bullet("Gems, VIP, and Franchise Stars are kept", system: "checkmark.seal.fill", good: true)
                bullet("Each star adds +\(Int(Balance.profitPerStar * 100))% profit forever", system: "star.fill", good: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .panel(Theme.panel)

            Button {
                if confirming {
                    let awarded = engine.prestige()
                    Haptics.success()
                    onToast("Franchised out for \(awarded) stars")
                    dismiss()
                } else {
                    confirming = true
                }
            } label: {
                Text(buttonTitle)
                    .font(Theme.body(16, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: engine.canPrestige ? (confirming ? Theme.negative : Theme.star) : Theme.locked,
                shadow: Theme.ink,
                disabled: !engine.canPrestige
            ))
            .disabled(!engine.canPrestige)

            if !engine.canPrestige {
                Text("Earn \(Format.currency(Balance.minimumLifetimeForPrestige)) lifetime to unlock your first franchise.")
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var buttonTitle: String {
        guard engine.canPrestige else { return "Not ready yet" }
        return confirming ? "Tap again to confirm" : "Franchise for \(engine.pendingStars) stars"
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke.opacity(0.5)).frame(height: 1).padding(.horizontal, 14)
    }

    private func statRow(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(value)
                .font(Theme.numeric(14))
                .foregroundStyle(highlight ? Theme.star : Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func bullet(_ text: String, system: String, good: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(good ? Theme.positive : Theme.textDim)
                .frame(width: 18)
            Text(text)
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }
}
