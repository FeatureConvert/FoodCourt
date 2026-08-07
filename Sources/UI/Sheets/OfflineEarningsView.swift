import SwiftUI

extension OfflineReport: Identifiable {
    /// Reports are transient and never shown two at a time; the payout is a fine identity.
    var id: String { "\(elapsed.rounded())-\(coins)" }
}

struct OfflineEarningsView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var ads: AdService
    @Environment(\.dismiss) private var dismiss

    let report: OfflineReport
    @State private var doubled = false

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            VStack(spacing: 14) {
                Text("WELCOME BACK")
                    .font(Theme.title(22))
                    .foregroundStyle(Theme.text)

                Text("Your staff kept working for \(Format.duration(report.credited))")
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    CoinIcon().frame(width: 34, height: 34)
                    Text(Format.currency(doubled ? report.coins * 2 : report.coins))
                        .font(Theme.numeric(30))
                        .foregroundStyle(Theme.coin)
                        .contentTransition(.numericText())
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .panel(Theme.panel)

                if report.wasCapped {
                    VStack(spacing: 4) {
                        Text("Offline earnings cap reached (\(Format.trim(report.capHours))h)")
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                        if !engine.state.entitlements.vip {
                            Text("VIP Pass and Night Shift research extend this")
                                .font(Theme.body(11, weight: .bold))
                                .foregroundStyle(Theme.gem)
                        }
                    }
                }

                Spacer(minLength: 0)

                if !doubled {
                    Button(action: doubleIt) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")
                            Text("Watch to double it")
                        }
                        .font(Theme.body(15, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Theme.positive, shadow: Theme.positive.opacity(0.5)))
                }

                Button {
                    dismiss()
                } label: {
                    Text(doubled ? "Collect" : "No thanks, collect")
                        .font(Theme.body(14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
            }
            .padding(20)

            // The ad has to be presented from inside this sheet. RootView's copy sits
            // below the sheet in the window, so playing it from there would hide the
            // countdown and the skip button behind this view.
            if ads.isPlaying {
                AdOverlayView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ads.isPlaying)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(ads.isPlaying)
    }

    /// The bonus is credited from the ad callback, so a cancelled ad pays nothing.
    private func doubleIt() {
        guard !doubled else { return }
        ads.play(engine: engine, reason: "offline") {
            engine.addCoins(report.coins)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { doubled = true }
            Haptics.success()
        }
    }
}
