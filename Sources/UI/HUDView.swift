import SwiftUI

struct HUDView: View {
    @EnvironmentObject private var engine: GameEngine
    let onDebug: () -> Void
    let onSettings: () -> Void
    let onStars: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                currencyPill {
                    CoinIcon().frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: -2) {
                        Text(Format.currency(engine.state.coins))
                            .font(Theme.numeric(19))
                            .foregroundStyle(Theme.text)
                        Text(Format.rate(engine.incomePerSecond))
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(Theme.positive)
                    }
                }

                currencyPill {
                    GemIcon().frame(width: 20, height: 20)
                    Text(Format.count(engine.state.gems))
                        .font(Theme.numeric(17))
                        .foregroundStyle(Theme.text)
                }

                if engine.state.lifetimeStars > 0 {
                    // Tapping the star pill is the way into Franchise and Research.
                    Button(action: onStars) {
                        currencyPill {
                            StarIcon().frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: -2) {
                                Text(Format.count(engine.state.stars))
                                    .font(Theme.numeric(16))
                                    .foregroundStyle(Theme.text)
                                Text("+\(Int(Double(engine.state.lifetimeStars) * Balance.profitPerStar * 100))%")
                                    .font(Theme.body(10, weight: .bold))
                                    .foregroundStyle(Theme.star)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.panel.opacity(0.92)))
                }
                .buttonStyle(.plain)
            }

            if !activeBoosts.isEmpty || engine.state.entitlements.vip {
                HStack(spacing: 6) {
                    if engine.state.entitlements.vip {
                        badge("VIP +\(Int(Balance.vipProfitBonus * 100))%", color: Theme.gem)
                    }
                    ForEach(activeBoosts) { boost in
                        badge("\(boost.label) · \(Format.duration(boost.remaining(at: engine.state.now)))",
                              color: Theme.coin)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.8) {
            #if DEBUG
            Haptics.thud()
            onDebug()
            #endif
        }
    }

    private var activeBoosts: [BoostState] { engine.state.activeBoosts }

    private func currencyPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 7) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .panel(Theme.panel.opacity(0.92), radius: 14)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.body(11, weight: .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }
}
