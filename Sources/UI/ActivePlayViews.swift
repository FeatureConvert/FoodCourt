import SwiftUI

/// The combo meter. Uses a `TimelineView` because the bar has to drain in real time while
/// the engine is otherwise silent between taps.
///
/// Always on screen now, combo running or not - it used to fade out entirely between
/// combos, which taught a new player nothing about the mechanic existing until they
/// stumbled into it by accident. Idle, it just prompts instead of disappearing.
struct ComboMeterView: View {
    @EnvironmentObject private var engine: GameEngine

    /// One color per tier in `ActivePlay.comboTiers` - MUST stay index-aligned and the same
    /// length as that array, not just "4, since that's how many tiers there used to be".
    /// This crashed on real devices (array index out of range in this file, not Combo.swift
    /// itself, which is why it survived that whole session's test suite - nothing here was
    /// under test) the moment a player with any comboBonusTaps investment climbed into the
    /// bonus-only tiers added past index 3: comboTiers grew to 8 entries, this array stayed
    /// at 4. Base tiers keep the original light-yellow-to-red climb; the bonus-only tiers
    /// above the base ceiling shift into purple and finish on gold, so reaching them reads
    /// as a distinct payoff for the investment, not just "a darker red".
    static let tierColors: [Color] = [
        Color(hex: "#FFF3B0"), Color(hex: "#FFC247"), Color(hex: "#FF6B3D"), Color(hex: "#D62839"),
        Color(hex: "#A61B4A"), Color(hex: "#7B1FA2"), Color(hex: "#4A148C"), Color(hex: "#FFD700"),
    ]

    var body: some View {
        // Capped like every other TimelineView in this codebase (StationListView,
        // TutorialOverlay) - plain `.animation` matches the display's refresh rate, which is
        // up to 120Hz on a ProMotion phone, and this view is mounted on the main board the
        // entire time the app is open, live combo or not. A draining bar reads just as
        // smoothly at 30fps; it was burning 4x the frames for zero visible benefit.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = engine.state.now
            let live = engine.combo.isLive(at: now)
            let bonus = engine.state.comboBonusTaps
            let multiplier = engine.combo.multiplier(bonusTaps: bonus)
            let active = engine.combo.activeTier(bonusTaps: bonus)
            let tier = ActivePlay.comboTiers[active.index]
            let tierColor = Self.tierColors[active.index]
            // Once real taps alone can't move the ladder any further this streak, "X/Y taps"
            // reads as a normal, about-to-fill progress bar - it never actually fills without
            // more comboBonusTaps investment, which looked indistinguishable from broken.
            let stuck = live && engine.combo.isAtPersonalCeiling(bonusTaps: bonus)
            let barFill = live && tier.taps > 0 ? Double(active.tapsDone) / Double(tier.taps) : 0
            // Clamped to 1: a manager trait's windowBonus (e.g. Crowd-Reader Cleo) extends
            // the window past `tier.window` itself, so right after a tap `remaining` can
            // briefly exceed it - unclamped, the fill capsule's width formula below went
            // wider than its own track and spilled past the frame.
            let timeLeft = live ? min(1, engine.combo.remaining(at: now) / tier.window) : 0

            HStack(spacing: 10) {
                GlyphIcon("flame.fill", tint: live ? tierColor : Theme.textDim)
                    .frame(width: 17, height: 17)
                    .scaleEffect(1 + 0.15 * timeLeft)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        if live {
                            Text("COMBO ×\(String(format: "%.1f", multiplier))")
                                .font(Theme.body(12, weight: .black))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            // "Needs more investment" rather than naming Research specifically -
                            // comboBonusTaps is Research + Legacy + Contract combined, and this
                            // player might be capped by any mix of the three.
                            Text(stuck ? "NEEDS MORE INVESTMENT" : "\(active.tapsDone)/\(tier.taps) taps")
                                .font(Theme.body(10, weight: .bold))
                                .foregroundStyle(Theme.textDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } else {
                            Text("Tap a station to start your combo")
                                .font(Theme.body(12, weight: .black))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.7))
                            // Depth sets the bar's ceiling, time-left drains it toward zero -
                            // each tap snaps it back out to that ceiling, then it visibly
                            // empties again until the next one. The ceiling and the drain
                            // speed both belong to whichever tier is currently active, so
                            // the bar visibly fills faster and drains quicker every time a
                            // new, hotter tier starts.
                            Capsule()
                                .fill(tierColor)
                                .frame(width: geo.size.width * barFill * timeLeft)
                        }
                    }
                    .frame(height: 7)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(live ? "Combo window remaining" : "No active combo")
                    .accessibilityValue(live ? "\(Int((timeLeft * 100).rounded())) percent" : "")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .panel(Theme.panelRaised, radius: 14)
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
            .litSurface(RoundedRectangle(cornerRadius: 14, style: .continuous),
                       fill: LinearGradient(colors: [Theme.coin, Theme.negative],
                                            startPoint: .leading, endPoint: .trailing),
                       lineWidth: 1.5, shadowRadius: 6, shadowY: 3)
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

                // The one figure on the stage the player is asked to look at and tap, so it
                // gets the blink even though it has to start a clock to do it - it is a
                // single sprite alive for five seconds, not a queue of six standing all game.
                BlinkingSprite(seed: seed, variant: isCritic ? .critic : .golden)
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
                         tint: engine.isBoostActive ? Theme.negative
                                                    : (engine.boostReady ? Theme.positive : Theme.locked),
                         badge: engine.boostReady,
                         cooldown: engine.boostReady ? nil :
                            // `remaining` counts down across the FULL span from activation to
                            // ready (the active 15 minutes plus the 30-minute cooldown after -
                            // see claimFreeBoost). `total` has to match that whole span, not
                            // just the cooldown-minutes constant, or the ring sits pinned at
                            // 0% for the entire active window and only starts filling once the
                            // boost ends - reading as if the cooldown were 15 minutes shorter
                            // than it actually is. Shown through BOTH the active window and the
                            // cooldown after - only the tint above distinguishes them, matching
                            // Rush Hour below (paired buttons meant to read as one control, not
                            // two - see the ring-track comment in circleButton).
                            Cooldown(remaining: engine.boostCooldownRemaining,
                                    total: ActivePlay.freeBoostHours * 3600
                                        + ActivePlay.freeBoostCooldownMinutes * 60),
                         action: onBoost)
                .tutorialHighlight(.coffeeButton)
                .accessibilityLabel("Coffee Break boost")
                .accessibilityValue(engine.isBoostActive ? "Active"
                    : engine.boostReady ? "Ready"
                    : "Ready in \(Format.duration(engine.boostCooldownRemaining))")

            circleButton(symbol: "timer",
                         tint: engine.rushActive ? Theme.negative
                                                 : (engine.rushReady ? Theme.coin : Theme.locked),
                         badge: engine.rushReady && !engine.rushActive,
                         cooldown: engine.rushReady ? nil :
                            // Same fix as Coffee Break above - rushAvailableAt is set from
                            // rushEndsAt, so `remaining` spans the run's own duration plus the
                            // 30-minute cooldown, not the cooldown alone. Also shown through the
                            // active window itself (not just nil'd out until it ends) - it used
                            // to go blank while running, so a paired Coffee Break + Rush Hour
                            // activation (the intended way to use them together) showed a timer
                            // on one button and nothing on the other, reading as two mismatched
                            // controls instead of the matched pair they're meant to be.
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
            // The badge wants top-trailing placement, but the cooldown ring and the
            // filled circle need a shared center - putting all three in one ZStack
            // with alignment: .topTrailing pinned the ring to the same corner as the badge
            // instead of centering it on the circle, so it rendered visibly offset. Centering
            // the circle and ring in their own default-aligned ZStack first, then overlaying
            // just the badge at top-trailing, keeps each piece aligned the way it should be.
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // The ring track is always drawn, ready/active included - it used to only
                    // appear during an actual cooldown, so whichever button wasn't cooling
                    // down at the moment (usually Rush, spent far less often than the free
                    // Coffee Break) looked like a plain flat dot next to the other one's ring,
                    // reading as two different controls instead of one pair. A prior attempt
                    // at this used white at 45% opacity, which measured out fine on paper but
                    // was confirmed on a real device to all but disappear against the warm
                    // stage backdrop - a light color needs real brightness contrast against a
                    // busy background to read, and half-transparent white over mid-tone brown
                    // doesn't have it. Theme.ink at high opacity instead: the same dark outline
                    // already proven to read here, on the badge dot's own border a few lines
                    // down, since a dark line's contrast comes from value, not hue, and holds
                    // up against any backdrop this stage art throws at it. Sized LARGER than
                    // the fill circle (not equal) so the ring's whole stroke width sits outside
                    // it - equal sizing left only a sliver visible past the fill's edge, too
                    // thin to read as a ring once it wasn't the bright gold progress arc
                    // filling most of it.
                    Circle()
                        .stroke(Theme.ink.opacity(0.85), lineWidth: 3.5)
                        .frame(width: 44, height: 44)
                    if let cooldown {
                        Circle()
                            .trim(from: 0, to: cooldown.progress)
                            .stroke(Theme.coin, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 44, height: 44)
                    }
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
