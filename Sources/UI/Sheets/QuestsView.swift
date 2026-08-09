import SwiftUI

struct QuestsView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case quests, achievements
        var id: String { rawValue }
        var title: String { self == .quests ? "Quests" : "Achievements" }
    }

    @State private var tab: Tab

    init(initialTab: Tab = .quests, onToast: @escaping (String) -> Void) {
        _tab = State(initialValue: initialTab)
        self.onToast = onToast
    }

    var body: some View {
        SheetScaffold(title: "Goals", subtitle: subtitle) {
            SegmentedTabs(selection: $tab) { $0.title }
                .padding(.bottom, 4)

            switch tab {
            case .quests: QuestsSection(onToast: onToast)
            case .achievements: AchievementsSection(onToast: onToast)
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case .quests: return "Three at a time — finish one and another arrives"
        case .achievements: return "\(engine.state.claimedAchievements.count) of \(AchievementCatalog.all.count) earned"
        }
    }
}

// MARK: - Quests

private struct QuestsSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void

    var body: some View {
        if let weekly = engine.state.weeklyQuest {
            weeklyRow(weekly)
        }

        ForEach(engine.state.quests) { quest in
            row(quest)
        }

        VStack(spacing: 4) {
            Text("\(Format.plural(engine.state.questsClaimed, "goal")) completed")
                .font(Theme.body(12, weight: .bold))
                .foregroundStyle(Theme.textDim)
            Text("Each one also pays \(Festival.ticketsPerQuest) festival tickets")
                .font(Theme.body(10, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// The oversized once-a-week challenge - same anatomy as a regular row, framed as an
    /// event with its own badge and claim path (`claimWeeklyQuest`).
    private func weeklyRow(_ quest: ActiveQuest) -> some View {
        let done = quest.isComplete
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("WEEKLY CHALLENGE")
                    .font(Theme.body(9, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.gem))
                Spacer(minLength: 0)
                Text("resets Monday")
                    .font(Theme.body(9, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 12) {
                GlyphIcon(quest.kind.symbol, tint: done ? Theme.positive : Theme.gem)
                    .frame(width: 20, height: 20)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title)
                        .font(Theme.body(14, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text(quest.progressLabel)
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(done ? Theme.positive : Theme.textDim)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    GemIcon().frame(width: 13, height: 13)
                    Text("\(quest.rewardGems)")
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.text)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.7))
                    Capsule()
                        .fill(done ? Theme.positive : Theme.gem)
                        .frame(width: geo.size.width * quest.fraction)
                }
            }
            .frame(height: 6)
            if done {
                Button {
                    if engine.claimWeeklyQuest() != nil {
                        Haptics.success()
                        sound.play(.bigReward)
                        onToast("Weekly Challenge complete! +\(quest.rewardGems) gems")
                    }
                } label: {
                    Text("Claim")
                        .font(Theme.body(13, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.positive,
                                               shadow: Theme.positive.opacity(0.5), radius: 12))
            }
        }
        .padding(12)
        .panel(done ? Theme.panelRaised : Theme.panel)
    }

    private func row(_ quest: ActiveQuest) -> some View {
        let done = quest.isComplete
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                GlyphIcon(quest.kind.symbol, tint: done ? Theme.positive : Theme.textDim)
                    .frame(width: 20, height: 20)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title)
                        .font(Theme.body(14, weight: .black))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(quest.progressLabel)
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(done ? Theme.positive : Theme.textDim)
                }
                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    GemIcon().frame(width: 13, height: 13)
                    Text("\(quest.rewardGems)")
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.text)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.7))
                    Capsule()
                        .fill(done ? Theme.positive : Theme.coin)
                        .frame(width: geo.size.width * quest.fraction)
                }
            }
            .frame(height: 6)

            if done {
                Button {
                    if let claimed = engine.claimQuest(id: quest.id) {
                        Haptics.success()
                        sound.play(.reward)
                        onToast("Claimed: \(claimed.title)")
                    }
                } label: {
                    Text("Claim")
                        .font(Theme.body(13, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.positive,
                                               shadow: Theme.positive.opacity(0.5), radius: 12))
            }
        }
        .padding(12)
        .panel(done ? Theme.panelRaised : Theme.panel)
    }
}

// MARK: - Achievements

private struct AchievementsSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void

    var body: some View {
        ForEach(AchievementCatalog.all) { spec in
            row(spec)
        }
    }

    private func row(_ spec: AchievementSpec) -> some View {
        let claimed = engine.state.claimedAchievements.contains(spec.id)
        let done = Achievements.isComplete(spec, state: engine.state)
        let fraction = Achievements.fraction(spec, state: engine.state)

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                GlyphIcon(spec.symbol, tint: claimed ? Theme.positive : (done ? Theme.coin : Theme.textDim))
                    .frame(width: 20, height: 20)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(spec.title)
                        .font(Theme.body(14, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text(spec.detail)
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)

                if claimed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.positive)
                } else {
                    HStack(spacing: 3) {
                        GemIcon().frame(width: 13, height: 13)
                        Text("\(spec.rewardGems)")
                            .font(Theme.numeric(13))
                            .foregroundStyle(Theme.text)
                    }
                }
            }

            if !claimed {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.ink.opacity(0.7))
                        Capsule()
                            .fill(done ? Theme.positive : Theme.coin)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 6)

                if done {
                    Button {
                        if let claimed = engine.claimAchievement(id: spec.id) {
                            Haptics.success()
                            sound.play(.reward)
                            onToast("Achievement: \(claimed.title)")
                        }
                    } label: {
                        Text("Claim")
                            .font(Theme.body(13, weight: .black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Theme.positive,
                                                   shadow: Theme.positive.opacity(0.5), radius: 12))
                }
            }
        }
        .padding(12)
        .panel(claimed || done ? Theme.panelRaised : Theme.panel)
        .opacity(claimed ? 0.75 : 1)
    }
}
