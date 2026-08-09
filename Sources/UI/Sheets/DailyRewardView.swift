import SwiftUI

/// The 7-day calendar. Split from its sheet wrapper so the Events hub can embed it as a tab
/// while the launch flow still presents it on its own.
struct DailyRewardSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void
    var onClaimed: (() -> Void)? = nil
    /// Deep-links for the Today's Plan checklist - only the launch presentation wires
    /// this; embedded uses (Events tab) leave it nil and the plan hides its chevrons.
    var onNavigate: ((ActiveSheet) -> Void)? = nil

    @State private var celebrating: Int?

    private var status: DailyClaimStatus { engine.dailyStatus }

    private var claimableDay: Int? {
        if case .available(let day) = status { return day }
        return nil
    }

    var subtitle: String {
        switch status {
        case .available(let day):
            return day == 1 && engine.state.daily.lastClaimedDay != nil
                ? "Streak restarted - day 1 is ready"
                : "Day \(day) is ready to claim"
        case .claimed(let next, _):
            return "Claimed today. Day \(next) unlocks tomorrow."
        }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(DailyRewards.calendar) { spec in
                dayTile(spec)
            }
        }

        Button(action: claim) {
            Text(claimableDay == nil ? "Come back tomorrow" : "Claim Day \(claimableDay ?? 1)")
                .font(Theme.body(16, weight: .black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: claimableDay == nil ? Theme.locked : Theme.positive,
            shadow: claimableDay == nil ? Theme.ink : Theme.positive.opacity(0.5),
            disabled: claimableDay == nil
        ))
        .disabled(claimableDay == nil)
        .padding(.top, 6)

        Text("Log in on consecutive days to keep your streak. Each claim also pays \(Festival.ticketsPerDaily) festival tickets.")
            .font(Theme.body(11, weight: .medium))
            .foregroundStyle(Theme.textDim)
            .multilineTextAlignment(.center)

        streakRow

        todaysPlan
    }

    /// The morning ritual, consolidated: everything claimable across the game in one
    /// checklist, each row one tap from the thing itself. Five sheet visits become one
    /// glance - the sheet a returning player already opens first thing.
    @ViewBuilder private var todaysPlan: some View {
        let quests = engine.claimableQuests
        let errands = engine.claimableErrands.count
        let festival = Festival.unclaimedCount(engine.state.festival,
                                               premiumActive: engine.festivalPremiumActive)
        if quests > 0 || errands > 0 || festival > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY'S PLAN")
                    .font(Theme.body(10, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textDim)
                if quests > 0 {
                    planRow("checkmark.circle.fill", "\(Format.plural(quests, "goal")) ready to claim",
                            destination: .quests(.quests))
                }
                if errands > 0 {
                    planRow("hourglass", "\(Format.plural(errands, "errand")) finished",
                            destination: .collection)
                }
                if festival > 0 {
                    planRow("ticket.fill", "\(Format.plural(festival, "festival reward")) waiting",
                            destination: .events(.festival))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .panel(Theme.panel)
        }
    }

    private func planRow(_ symbol: String, _ text: String, destination: ActiveSheet) -> some View {
        Button {
            onNavigate?(destination)
        } label: {
            HStack(spacing: 8) {
                GlyphIcon(symbol, tint: Theme.coin)
                    .frame(width: 15, height: 15)
                Text(text)
                    .font(Theme.body(12, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                if onNavigate != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onNavigate == nil)
    }

    private var streakRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                GlyphIcon("flame.fill", tint: Theme.coin)
                    .frame(width: 15, height: 15)
                Text("\(Format.plural(engine.state.daily.streakLength, "day")) streak")
                    .font(Theme.body(13, weight: .black))
                    .foregroundStyle(Theme.text)
                // Loss aversion made visible: the next milestone and the distance to it.
                if let next = DailyRewards.streakMilestones.first(where: { $0.day > engine.state.daily.streakLength }) {
                    Text("\(next.day - engine.state.daily.streakLength) days to \(next.gems) gems")
                        .font(Theme.body(10, weight: .bold))
                        .foregroundStyle(Theme.gem)
                }
                if engine.state.daily.streakFreezes > 0 {
                    HStack(spacing: 3) {
                        GlyphIcon("snowflake", tint: Theme.textDim)
                            .frame(width: 12, height: 12)
                        Text("×\(engine.state.daily.streakFreezes)")
                    }
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
            }

            ForEach(engine.claimableStreakMilestones, id: \.day) { milestone in
                Button {
                    if let gems = engine.claimStreakMilestone(day: milestone.day) {
                        Haptics.success()
                        sound.play(.reward)
                        onToast("\(milestone.day)-day streak: +\(gems) gems")
                    }
                } label: {
                    HStack {
                        Text("\(milestone.day)-day streak reward")
                            .font(Theme.body(12, weight: .bold))
                        Spacer()
                        HStack(spacing: 3) {
                            GemIcon().frame(width: 12, height: 12)
                            Text("\(milestone.gems)")
                        }
                        .font(Theme.numeric(12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.positive,
                                               shadow: Theme.positive.opacity(0.5), radius: 10))
            }
        }
        .padding(.top, 4)
    }

    private func dayTile(_ spec: DailyRewardSpec) -> some View {
        let claimable = claimableDay == spec.day
        let claimed = isClaimed(spec.day)

        return VStack(spacing: 6) {
            Text("DAY \(spec.day)")
                .font(Theme.body(10, weight: .black))
                .foregroundStyle(claimable ? Theme.ink : Theme.textDim)

            rewardArt(spec).frame(height: 34)

            Text(spec.title)
                .font(Theme.body(10, weight: .bold))
                .foregroundStyle(claimable ? Theme.ink : Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 26)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(claimable ? Theme.coin : (spec.isGrand ? Theme.panelRaised : Theme.panel))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(spec.isGrand ? Theme.coin : Theme.stroke, lineWidth: spec.isGrand ? 2 : 1.5)
                )
        )
        .overlay(alignment: .topTrailing) {
            if claimed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.positive)
                    .padding(6)
            }
        }
        .scaleEffect(celebrating == spec.day ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: celebrating)
    }

    @ViewBuilder
    private func rewardArt(_ spec: DailyRewardSpec) -> some View {
        switch spec.kind {
        case .coins:
            CoinIcon().frame(width: 32, height: 32)
        case .gems:
            GemIcon().frame(width: 30, height: 30)
        case .boost:
            GlyphIcon("bolt.fill", tint: Theme.coin)
                .frame(width: 26, height: 26)
        case .grand:
            HStack(spacing: -6) {
                GemIcon().frame(width: 26, height: 26)
                CoinIcon().frame(width: 26, height: 26)
                StarIcon().frame(width: 26, height: 26)
            }
        }
    }

    private func isClaimed(_ day: Int) -> Bool {
        switch status {
        case .available(let current): return day < current
        case .claimed(let next, _): return next == 1 ? true : day < next
        }
    }

    private func claim() {
        guard let payout = engine.claimDaily() else {
            onToast("Already claimed today")
            return
        }
        Haptics.success()
        sound.play(.reward)
        celebrating = payout.day

        var parts: [String] = []
        if payout.coins > 0 { parts.append(Format.currency(payout.coins) + " coins") }
        if payout.gems > 0 { parts.append("\(payout.gems) gems") }
        if let boost = payout.boost { parts.append(boost.label) }
        onToast("Day \(payout.day): " + parts.joined(separator: " + "))

        onClaimed?()
    }
}

/// Standalone presentation used when the game opens on a fresh day.
struct DailyRewardView: View {
    @EnvironmentObject private var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    let onToast: (String) -> Void
    var onNavigate: ((ActiveSheet) -> Void)? = nil

    var body: some View {
        SheetScaffold(title: "Daily Rewards", subtitle: subtitle) {
            DailyRewardSection(
                onToast: onToast,
                onClaimed: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
                },
                onNavigate: onNavigate
            )
        }
    }

    private var subtitle: String {
        switch engine.dailyStatus {
        case .available(let day):
            return day == 1 && engine.state.daily.lastClaimedDay != nil
                ? "Streak restarted - day 1 is ready"
                : "Day \(day) is ready to claim"
        case .claimed(let next, _):
            return "Claimed today. Day \(next) unlocks tomorrow."
        }
    }
}
