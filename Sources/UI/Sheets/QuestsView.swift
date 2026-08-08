import SwiftUI

struct QuestsView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case quests, achievements
        var id: String { rawValue }
        var title: String { self == .quests ? "Quests" : "Achievements" }
    }

    @State private var tab: Tab = .quests

    var body: some View {
        SheetScaffold(title: "Goals", subtitle: subtitle) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
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
    let onToast: (String) -> Void

    var body: some View {
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

    private func row(_ quest: ActiveQuest) -> some View {
        let done = quest.isComplete
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: quest.kind.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(done ? Theme.positive : Theme.textDim)
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
                Image(systemName: spec.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(claimed ? Theme.positive : (done ? Theme.coin : Theme.textDim))
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
