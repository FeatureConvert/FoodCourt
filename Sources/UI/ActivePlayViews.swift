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
                            // Depth sets the bar's ceiling, time-left drains it toward zero -
                            // each tap snaps it back out to that ceiling, then it visibly
                            // empties again until the next one.
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.coin, Theme.negative],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * fill * timeLeft)
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
///
/// One in twenty of these is a VIP critic worth ten times the tip. The engine has always known
/// which is which (`GoldenCustomer.isCritic`), and the Help screen has always described the
/// tier, but both rendered identically - so the player only found out which one they had caught
/// from the toast *after* spending the tap. The critic now reads as its own character: plum
/// suit, gold lapels and bow tie, monocle, clipboard, and a dashed ring around the whole
/// figure. The crown itself comes from the sprite now, where it can sit correctly against the
/// hair rather than being pinned over it at a fixed offset.
struct GoldenCustomerView: View {
    let seed: Int
    var isCritic: Bool = false
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.coin.opacity(isCritic ? 0.5 : 0.85), .clear],
                                         center: .center, startRadius: 2, endRadius: 34))
                    .frame(width: 68, height: 68)
                    .scaleEffect(pulse ? 1.15 : 0.9)

                if isCritic {
                    criticRing
                } else {
                    GoldenSparkles()
                        .frame(width: 68, height: 68)
                }

                CustomerSprite(seed: seed, variant: isCritic ? .critic : .golden)
                    .equatable()
                    .frame(width: 46, height: 64)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            // Previously unconditional - this repeating animation predates the reduce-motion
            // pass and was the one continuous loop on the stage that ignored the setting.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel(isCritic ? "VIP critic customer" : "Golden customer")
        .accessibilityHint(isCritic ? "Double tap to collect a x10 tip" : "Double tap to collect a tip")
        .transition(.scale.combined(with: .opacity))
    }

    /// Design's "Legendary rotating highlight" language applied to the Critic specifically -
    /// same ~112 deg/s rate as `ManagerRarityFrame`'s legendary ring, same reduce-motion pose
    /// (parked at -90, 12 o'clock) rather than a second bespoke animation.
    private var criticRing: some View {
        Group {
            if reduceMotion {
                criticRingShape.rotationEffect(.degrees(-90))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    criticRingShape.rotationEffect(.degrees(t * 112))
                }
            }
        }
    }

    private var criticRingShape: some View {
        Circle()
            .stroke(Theme.coin.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, dash: [14, 22]))
            .frame(width: 62, height: 62)
    }
}

/// Four eight-point sparkles pulsing around the Golden Customer - design spec: 1.8s cycle,
/// phase-offset per sparkle, opacity 0.15->1 and scale 0.7->1.15 at the peak. One shared
/// `TimelineView` drives all four rather than four independent ones; each sparkle only
/// differs by a phase added before the wave function, not by its own clock.
private struct GoldenSparkles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fractional position within the view + phase offset in seconds, lifted from design's
    /// own `goldExtras` layout (four corners scattered around the figure, not a neat ring).
    private static let sparkles: [(x: CGFloat, y: CGFloat, phase: Double)] = [
        (0.16, 0.26, 0.0), (0.85, 0.18, 0.6), (0.89, 0.66, 1.2), (0.11, 0.72, 0.9),
    ]

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ForEach(Array(Self.sparkles.enumerated()), id: \.offset) { _, s in
                        // Raised cosine: smooth ease in/out between the trough and peak,
                        // matching the CSS keyframe's implicit easing rather than a linear pulse.
                        let wave = (1 - cos((t + s.phase) / 1.8 * 2 * .pi)) / 2
                        SparkleShape()
                            .fill(Theme.coin)
                            .frame(width: 9, height: 9)
                            .opacity(0.15 + wave * 0.85)
                            .scaleEffect(0.7 + wave * 0.45)
                            .position(x: geo.size.width * s.x, y: geo.size.height * s.y)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// The eight-point sparkle outline itself, straight from design's SVG path.
private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let scale = min(rect.width, rect.height) / 11 // path spans -5.5...5.5 on each axis
        let points: [(CGFloat, CGFloat)] = [
            (0, -5.5), (1.5, -1.5), (5.5, 0), (1.5, 1.5),
            (0, 5.5), (-1.5, 1.5), (-5.5, 0), (-1.5, -1.5),
        ]
        var path = Path()
        path.move(to: CGPoint(x: cx + points[0].0 * scale, y: cy + points[0].1 * scale))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: cx + point.0 * scale, y: cy + point.1 * scale))
        }
        path.closeSubpath()
        return path
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
