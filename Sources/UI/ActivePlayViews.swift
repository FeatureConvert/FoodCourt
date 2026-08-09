import SwiftUI

/// The combo meter. Uses a `TimelineView` because the bar has to drain in real time while
/// the engine is otherwise silent between taps.
struct ComboMeterView: View {
    @EnvironmentObject private var engine: GameEngine

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = engine.state.now
            let live = engine.combo.isLive(at: now)
            let steps = engine.state.comboMaxSteps
            let multiplier = engine.combo.multiplier(maxSteps: steps)
            let fill = engine.combo.fraction(maxSteps: steps)
            let timeLeft = engine.combo.remaining(at: now) / ActivePlay.comboWindow

            HStack(spacing: 10) {
                GlyphIcon("flame.fill", tint: Theme.coin)
                    .frame(width: 17, height: 17)
                    .scaleEffect(1 + 0.15 * timeLeft)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("COMBO ×\(String(format: "%.1f", multiplier))")
                            .font(Theme.body(12, weight: .black))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(engine.combo.count) taps")
                            .font(Theme.body(10, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.7))
                            // Fill shows combo depth, the trailing edge shows time left.
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.coin, Theme.negative],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * fill)
                            Capsule()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 3)
                                .offset(x: max(0, geo.size.width * timeLeft - 3))
                        }
                    }
                    .frame(height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .panel(Theme.panelRaised, radius: 14)
            .opacity(live ? 1 : 0)
            .scaleEffect(live ? 1 : 0.96, anchor: .top)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: live)
            // Reserves its natural height whether live or not and only fades in place -
            // collapsing to zero height here used to shift the station list up and down
            // every time a combo started or expired, right under the player's thumb while
            // they were actively tapping.
        }
        .allowsHitTesting(false)
    }
}

/// Countdown banner shown while Rush Hour is running.
struct RushBannerView: View {
    @EnvironmentObject private var engine: GameEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 8) {
                GlyphIcon("timer", tint: Theme.ink)
                    .frame(width: 16, height: 16)
                Text("RUSH HOUR ×\(Format.trim(ActivePlay.rushMultiplier))")
                    .font(Theme.body(13, weight: .black))
                Spacer()
                Text(Format.clock(engine.rushRemaining))
                    .font(Theme.numeric(14))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.coin, Theme.negative],
                                         startPoint: .leading, endPoint: .trailing))
            )
        }
    }
}

/// The rare VIP. Gold, pulsing, and on a five second fuse.
struct GoldenCustomerView: View {
    let seed: Int
    let onTap: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.coin.opacity(0.85), .clear],
                                         center: .center, startRadius: 2, endRadius: 34))
                    .frame(width: 68, height: 68)
                    .scaleEffect(pulse ? 1.15 : 0.9)

                CustomerSprite(seed: seed)
                    .equatable()
                    .frame(width: 46, height: 64)
                    .overlay(
                        CrownIcon()
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .offset(y: -30)
                    )
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

/// Floating action button stack on the venue stage: free boost and Rush Hour.
struct StageActionsView: View {
    @EnvironmentObject private var engine: GameEngine
    let onBoost: () -> Void
    let onRush: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            circleButton(symbol: "cup.and.saucer.fill",
                         tint: engine.boostReady ? Theme.positive : Theme.locked,
                         badge: engine.boostReady,
                         cooldown: engine.boostReady ? nil :
                            Cooldown(remaining: engine.boostCooldownRemaining,
                                    total: ActivePlay.freeBoostCooldownMinutes * 60),
                         action: onBoost)
                .tutorialHighlight(.coffeeButton)

            circleButton(symbol: "timer",
                         tint: engine.rushActive ? Theme.negative
                                                 : (engine.rushReady ? Theme.coin : Theme.locked),
                         badge: engine.rushReady && !engine.rushActive,
                         cooldown: (engine.rushReady || engine.rushActive) ? nil :
                            Cooldown(remaining: engine.rushCooldownRemaining,
                                    total: ActivePlay.rushCooldownMinutes * 60),
                         action: onRush)
        }
    }

    /// How far through its cooldown a boost is, so the ring can fill toward ready rather than
    /// just leaving the button looking permanently locked with no sense of how much longer.
    private struct Cooldown {
        let remaining: TimeInterval
        let total: TimeInterval
        var progress: Double { total > 0 ? min(1, max(0, 1 - remaining / total)) : 1 }
    }

    private func circleButton(symbol: String, tint: Color, badge: Bool,
                              cooldown: Cooldown?,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(tint)
                        .frame(width: 42, height: 42)
                        .overlay(
                            GlyphIcon(symbol, tint: Theme.ink)
                                .frame(width: 20, height: 20)
                                .opacity(cooldown == nil ? 1 : 0.5)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    if let cooldown {
                        Circle()
                            .trim(from: 0, to: cooldown.progress)
                            .stroke(Theme.coin, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 48, height: 48)
                    }
                    if badge {
                        Circle().fill(Theme.negative)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Theme.ink, lineWidth: 1.5))
                    }
                }
                .frame(width: 48, height: 46, alignment: .center)

                if let cooldown {
                    Text(Format.clock(cooldown.remaining))
                        .font(Theme.numeric(9))
                        .foregroundStyle(Theme.text)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.ink.opacity(0.85)))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
