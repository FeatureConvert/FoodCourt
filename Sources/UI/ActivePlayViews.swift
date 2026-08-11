import SwiftUI

/// The combo meter. Uses a `TimelineView` because the bar has to drain in real time while
/// the engine is otherwise silent between taps.
struct ComboMeterView: View {
    @EnvironmentObject private var engine: GameEngine

    var body: some View {
        // Capped like every other TimelineView in this codebase (StationListView,
        // TutorialOverlay) - plain `.animation` matches the display's refresh rate, which is
        // up to 120Hz on a ProMotion phone, and this view is mounted on the main board the
        // entire time the app is open, live combo or not. A draining bar reads just as
        // smoothly at 30fps; it was burning 4x the frames for zero visible benefit.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
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
                            // `remaining` counts down across the FULL span from activation to
                            // ready (the active 15 minutes plus the 30-minute cooldown after -
                            // see claimFreeBoost). `total` has to match that whole span, not
                            // just the cooldown-minutes constant, or the ring sits pinned at
                            // 0% for the entire active window and only starts filling once the
                            // boost ends - reading as if the cooldown were 15 minutes shorter
                            // than it actually is.
                            Cooldown(remaining: engine.boostCooldownRemaining,
                                    total: ActivePlay.freeBoostHours * 3600
                                        + ActivePlay.freeBoostCooldownMinutes * 60),
                         action: onBoost)
                .tutorialHighlight(.coffeeButton)
                .accessibilityLabel("Coffee Break boost")
                .accessibilityValue(engine.boostReady ? "Ready"
                    : "Ready in \(Format.duration(engine.boostCooldownRemaining))")

            circleButton(symbol: "timer",
                         tint: engine.rushActive ? Theme.negative
                                                 : (engine.rushReady ? Theme.coin : Theme.locked),
                         badge: engine.rushReady && !engine.rushActive,
                         cooldown: (engine.rushReady || engine.rushActive) ? nil :
                            // Same fix as Coffee Break above - rushAvailableAt is set from
                            // rushEndsAt, so `remaining` spans the run's own duration plus the
                            // 30-minute cooldown, not the cooldown alone.
                            Cooldown(remaining: engine.rushCooldownRemaining,
                                    total: engine.state.rushDuration
                                        + ActivePlay.rushCooldownMinutes * 60),
                         action: onRush)
                .accessibilityLabel("Rush Hour")
                .accessibilityValue(engine.rushActive ? "Running"
                    : (engine.rushReady ? "Ready" : "Ready in \(Format.duration(engine.rushCooldownRemaining))"))
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
            // The badge wants top-trailing placement, but the cooldown ring (48pt) and the
            // filled circle (42pt) need a shared center - putting all three in one ZStack
            // with alignment: .topTrailing pinned the ring to the same corner as the badge
            // instead of centering it on the circle, so it rendered visibly offset. Centering
            // the circle and ring in their own default-aligned ZStack first, then overlaying
            // just the badge at top-trailing, keeps each piece aligned the way it should be.
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 42, height: 42)
                        .overlay(
                            VStack(spacing: 1) {
                                GlyphIcon(symbol, tint: Theme.ink)
                                    .frame(width: cooldown == nil ? 20 : 15, height: cooldown == nil ? 20 : 15)
                                    .opacity(cooldown == nil ? 1 : 0.6)
                                if let cooldown {
                                    // Sits below the symbol, inside the same circle, rather than
                                    // as a separate label - keeps the button a single glanceable
                                    // unit instead of two things stacked on top of each other.
                                    Text(Format.clock(cooldown.remaining))
                                        .font(.system(size: 7.5, weight: .black, design: .rounded))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .fixedSize()
                                }
                            }
                            .offset(y: cooldown == nil ? 0 : -1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    if let cooldown {
                        Circle()
                            .trim(from: 0, to: cooldown.progress)
                            .stroke(Theme.coin, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 48, height: 48)
                    }
                }
                if badge {
                    Circle().fill(Theme.negative)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: 1.5))
                }
            }
            .frame(width: 48, height: 46, alignment: .center)
        }
        .buttonStyle(.plain)
    }
}
