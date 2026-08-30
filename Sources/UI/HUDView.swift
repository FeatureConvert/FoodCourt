import SwiftUI

struct HUDView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onDebug: () -> Void
    let onSettings: () -> Void
    let onStars: () -> Void
    let onHelp: () -> Void
    /// Badges like the active Contract name used to be inert text - no way to learn what
    /// "Investor Showcase" actually does without already knowing. Tapping one now surfaces
    /// its real effect through this same callback RootView already wires to showToast.
    let onBadgeInfo: (String) -> Void

    /// Which goal's explainer is unfolded - keyed by id so advancing to the next goal
    /// collapses the chip again on its own.
    @State private var expandedGoalID: String?

    var body: some View {
        // Every number in this row used to be `.fixedSize()`, which refuses to compress at
        // any cost. Once a player prestiges, the star pill joins the coin and gem pills and
        // the three together demand more than the row has - the Spacer collapsed to zero and
        // the help/settings buttons were pushed clean off the right edge, unreachable. The
        // numbers now scale down to fit instead, and the two buttons take layout priority so
        // they are always laid out before the pills compete for what's left.
        //
        // minimumScaleFactor is a FRACTION of each Text's own font size, not an absolute
        // floor - so two Texts sharing a column (and so a proposed width) but starting from
        // different point sizes hit different absolute minimum widths at the same fraction.
        // A flat 0.6, then a flat 0.45, both still left the 19pt coin balance truncating
        // ("60...", then later "87...") while the 11pt income-rate line right under it
        // rendered in full - the smaller line's fraction bottoms out several points lower in
        // absolute size, so it can keep shrinking to fit long after the balance line has
        // already hit ITS floor and given up. Every line below instead targets the same
        // absolute floor (~8pt), computed per line as 8 / the line's own font size, so under
        // identical horizontal pressure they all run out of room to shrink at the same time
        // rather than one line truncating while its neighbor sails through.
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                currencyPill {
                    CoinIcon().frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: -2) {
                        Text(Format.currency(engine.state.coins))
                            .font(Theme.numeric(19))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(hudMinScale(for: 19))
                        Text(Format.rate(engine.incomePerSecond))
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(Theme.positive)
                            .lineLimit(1)
                            .minimumScaleFactor(hudMinScale(for: 11))
                    }
                }

                currencyPill {
                    // CoinIcon draws a near-edge-to-edge circle (86% of its box); GemIcon's
                    // diamond has much more built-in padding and a pointed silhouette, so it
                    // read visibly smaller than the coin even at a near-identical frame size
                    // (20pt vs 22pt). 27pt brings its actual visual weight to parity instead
                    // of just matching the nominal frame number.
                    GemIcon().frame(width: 27, height: 27)
                    Text(Format.count(engine.state.gems))
                        .font(Theme.numeric(17))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(hudMinScale(for: 17))
                }

                if engine.state.lifetimeStars > 0 || engine.canPrestige {
                    // Tapping the star pill is the way into Franchise and Research.
                    // Must surface once canPrestige is true, even before the player's
                    // first prestige (lifetimeStars == 0) - otherwise there is no
                    // entry point into the sheet at all.
                    Button(action: onStars) {
                        currencyPill {
                            StarIcon().frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: -2) {
                                Text(Format.count(engine.state.stars))
                                    .font(Theme.numeric(16))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(hudMinScale(for: 16))
                                // The anticipation meter: pending stars accrue live, so
                                // the payoff visibly builds between franchises - the
                                // strongest pull the game owns, previously invisible here.
                                if engine.pendingStars > 0 {
                                    Text("+\(Format.count(engine.pendingStars)) ready")
                                        .font(Theme.body(10, weight: .bold))
                                        .foregroundStyle(Theme.positive)
                                        .lineLimit(1)
                                        .minimumScaleFactor(hudMinScale(for: 10))
                                } else {
                                    Text(Format.bonus(multiplier: Balance.starMultiplier(stars: engine.state.lifetimeStars)))
                                        .font(Theme.body(10, weight: .bold))
                                        .foregroundStyle(Theme.star)
                                        .lineLimit(1)
                                        .minimumScaleFactor(hudMinScale(for: 10))
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .pulsingHighlight(engine.shouldNudgePrestige, cornerRadius: 14)
                    .accessibilityLabel("Franchise and Research")
                    .accessibilityValue(engine.pendingStars > 0
                        ? "\(engine.pendingStars) stars ready to claim"
                        : "\(engine.state.stars) stars to spend")
                }

                Spacer(minLength: 0)

                Button(action: onHelp) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.panel.opacity(0.92)))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityLabel("Help")

                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.panel.opacity(0.92)))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityLabel("Settings")
            }

            if !activeBoosts.isEmpty || engine.state.entitlements.vip
                || engine.state.entitlements.mogul || engine.state.isHappyHour()
                || activeContractBadge != nil || errandBadge != nil || faceOffBadge != nil {
                HStack(spacing: 6) {
                    if let contract = activeContractBadge, let detail = engine.state.contract?.detail {
                        badge(contract, detail: detail, color: Theme.star)
                    }
                    // Errands and Face-Offs otherwise only show their status inside the
                    // Collection sheet - checking on either meant re-opening it repeatedly,
                    // unlike a boost's countdown which is always visible right here.
                    if let errandBadge {
                        badge(errandBadge.text, detail: errandBadge.detail,
                              color: errandBadge.ready ? Theme.positive : Theme.coin)
                    }
                    if let faceOffBadge {
                        badge(faceOffBadge.text, detail: faceOffBadge.detail,
                              color: faceOffBadge.ready ? Theme.positive : Theme.coin)
                    }
                    if engine.state.isHappyHour() {
                        badge("HAPPY HOUR ×\(Format.trim(ActivePlay.happyHourMultiplier))",
                              detail: "A daily 6-8pm window: ×\(Format.trim(ActivePlay.happyHourMultiplier)) on every payout and better odds of a Golden Customer.",
                              color: Theme.positive)
                    }
                    if engine.state.entitlements.vip {
                        badge("VIP +\(Int(Balance.vipProfitBonus * 100))%",
                              detail: "+\(Int(Balance.vipProfitBonus * 100))% profit forever, \(Int(Balance.offlineCapHoursVIP))h offline earnings, and a Carnival Pass every season.",
                              color: Theme.gem)
                    }
                    if engine.state.entitlements.mogul {
                        badge("MOGUL +\(Int(Balance.mogulProfitBonus * 100))%",
                              detail: "+\(Int(Balance.mogulProfitBonus * 100))% profit forever and +\(Int(Balance.mogulOfflineCapBonusHours))h offline cap, stacking with VIP.",
                              color: Theme.star)
                    }
                    ForEach(activeBoosts) { boost in
                        badge("\(boost.label) · \(Format.duration(boost.remaining(at: engine.state.now)))",
                              detail: "\(boost.label) - ends in \(Format.duration(boost.remaining(at: engine.state.now))).",
                              color: Theme.coin)
                    }
                    Spacer(minLength: 0)
                }
            }

            // The always-on answer to "what should I be doing?" - see GoalDirector. Hidden
            // during the coach-card tutorial so two guidance systems never talk at once.
            if engine.state.tutorial.finished,
               let goal = GoalDirector.currentGoal(for: engine.state) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        expandedGoalID = expandedGoalID == goal.id ? nil : goal.id
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "scope")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Theme.coin)
                            Text("NEXT GOAL")
                                .font(Theme.body(9, weight: .black))
                                .tracking(0.6)
                                .foregroundStyle(Theme.textDim)
                            Text(goal.title)
                                .font(Theme.body(11, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: expandedGoalID == goal.id ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Theme.textDim)
                        }
                        if expandedGoalID == goal.id {
                            Text(goal.detail)
                                .font(Theme.body(11, weight: .medium))
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(Theme.panel.opacity(0.92), radius: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.8) {
            #if DEBUG
            Haptics.thud()
            sound.play(.purchase)
            onDebug()
            #endif
        }
    }

    /// Every currency-row line's minimumScaleFactor, expressed as a fraction of ITS OWN font
    /// size, converges on the same absolute floor instead - see the comment at the top of
    /// `body` for why a shared fraction doesn't do that.
    private func hudMinScale(for fontSize: CGFloat) -> CGFloat {
        8 / fontSize
    }

    private var activeBoosts: [BoostState] { engine.state.activeBoosts }

    /// The run's contract, badged so its modifiers are never invisible - the vanilla
    /// "straight" pick shows nothing, matching how no badge meant no modifiers before.
    private var activeContractBadge: String? {
        guard let contract = engine.state.contract, contract.id != "straight" else { return nil }
        return contract.title.uppercased()
    }

    private var errandBadge: (text: String, detail: String, ready: Bool)? {
        let errands = engine.state.errands
        guard !errands.isEmpty else { return nil }
        let readyCount = errands.filter { $0.isComplete(at: engine.state.now) }.count
        if readyCount > 0 {
            let label = readyCount > 1 ? "ERRANDS READY (\(readyCount))" : "ERRAND READY"
            return (label, "Collect it from the Staff sheet.", true)
        }
        let soonest = errands.map { $0.remaining(at: engine.state.now) }.min() ?? 0
        return ("ERRAND · \(Format.duration(soonest))",
                "Back in \(Format.duration(soonest)) - collect it from the Staff sheet.", false)
    }

    private var faceOffBadge: (text: String, detail: String, ready: Bool)? {
        guard let expedition = engine.state.expedition else { return nil }
        if expedition.isComplete(at: engine.state.now) {
            return ("FACE-OFF READY", "Results are in - see them in the Staff sheet.", true)
        }
        let remaining = expedition.remaining(at: engine.state.now)
        return ("FACE-OFF · \(Format.duration(remaining))",
                "Back in \(Format.duration(remaining)) - see it in the Staff sheet.", false)
    }

    private func currencyPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 7) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .panel(Theme.panel.opacity(0.92), radius: 14)
    }

    private func badge(_ text: String, detail: String, color: Color) -> some View {
        Button {
            Haptics.tap()
            sound.play(.tap)
            onBadgeInfo(detail)
        } label: {
            Text(text)
                .font(Theme.body(11, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Double tap for details")
    }
}
