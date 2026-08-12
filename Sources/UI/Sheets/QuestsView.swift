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

    private var cateringReady: Bool {
        if let order = engine.state.catering, order.expiresAt > engine.state.now, !order.claimed {
            return order.isComplete
        }
        return false
    }

    private var totalClaimable: Int {
        engine.claimableQuests + (cateringReady ? 1 : 0)
    }

    var body: some View {
        // Only worth a dedicated button once there's more than one thing to gather up -
        // for a single claimable, the row's own Claim button is no extra reach.
        if totalClaimable > 1 {
            IntroBanner(key: IntroKey.claimAllQuests, symbol: "checkmark.circle.fill",
                        title: "Claim everything at once",
                        detail: "When more than one goal is ready, this collects them all in a single tap instead of one at a time.")
            claimAllButton
        }

        // Paced: the oversized weekly ask waits until the guided opening is done - a
        // tutorial-hour player should meet three small goals, not a 40,000-dish wall.
        if let weekly = engine.state.weeklyQuest, engine.state.tutorial.finished {
            weeklyRow(weekly)
        }

        if let order = engine.state.catering, order.expiresAt > engine.state.now, !order.claimed {
            IntroBanner(key: IntroKey.catering, symbol: "takeoutbag.and.cup.and.straw.fill",
                        title: "Catering orders",
                        detail: "One big order a day, naming specific stations - the named counters have to actually run to fill it. Finish before it expires for gems, coins, and tickets; a new order arrives every day either way.")
            cateringRow(order)
        }

        // Claimable quests float to the top so a player never has to hunt/scroll for the
        // one thing here that actually needs a tap.
        ForEach(engine.state.quests.sorted { $0.isComplete && !$1.isComplete }) { quest in
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

    /// Today's catering order: per-station progress toward a composed, expiring ask.
    private func cateringRow(_ order: CateringOrder) -> some View {
        let done = order.isComplete
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("CATERING · \(Balance.venue(order.venue).name.uppercased())")
                    .font(Theme.body(9, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.coin))
                Spacer(minLength: 0)
                Text("\(Format.duration(order.expiresAt.timeIntervalSince(engine.state.now))) left")
                    .font(Theme.body(9, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            // Guards against a stale order rolled against an older catalog naming a station
            // index the current build no longer has - skip it rather than crash on the subscript.
            ForEach(order.requirements.keys.sorted().filter {
                Balance.venue(order.venue).stations.indices.contains($0)
            }, id: \.self) { station in
                let spec = Balance.venue(order.venue).stations[station]
                let need = order.requirements[station] ?? 0
                let have = min(order.progress[station] ?? 0, need)
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        FoodSprite(art: spec.art, colors: spec.colors)
                            .equatable()
                            .frame(width: 22, height: 22)
                        Text(spec.name)
                            .font(Theme.body(12, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        Text("\(Format.count(have)) / \(Format.count(need))")
                            .font(Theme.numeric(11))
                            .foregroundStyle(have >= need ? Theme.positive : Theme.textDim)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.7))
                            Capsule()
                                .fill(have >= need ? Theme.positive : Theme.coin)
                                .frame(width: geo.size.width * order.fraction(station: station))
                        }
                    }
                    .frame(height: 5)
                }
            }
            HStack(spacing: 4) {
                GemIcon().frame(width: 13, height: 13)
                Text("\(order.rewardGems) + \(Format.trim(order.rewardIncomeSeconds / 60))m income + tickets")
                    .font(Theme.body(10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                Spacer(minLength: 0)
            }
            if done {
                Button {
                    if engine.claimCatering() != nil {
                        Haptics.success()
                        sound.play(.bigReward)
                        onToast("Catering delivered! +\(order.rewardGems) gems")
                    }
                } label: {
                    Text("Deliver")
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

    private var claimAllButton: some View {
        Button {
            let claimed = engine.claimAllQuests()
            guard claimed > 0 else { return }
            Haptics.success()
            sound.play(.bigReward)
            onToast("Claimed \(Format.plural(claimed, "item"))")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Claim All (\(totalClaimable))")
            }
            .font(Theme.body(13, weight: .black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.positive, shadow: Theme.positive.opacity(0.5), radius: 12))
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

    /// Claimable-but-unclaimed first, same reasoning as the quest list - a player shouldn't
    /// have to scroll the whole 27-entry catalog to find the one row with gems waiting.
    /// Stable otherwise, so the catalog's own order still governs everything else.
    private var sortedSpecs: [AchievementSpec] {
        AchievementCatalog.all.sorted { lhs, rhs in
            let lhsClaimable = Achievements.isComplete(lhs, state: engine.state)
                && !engine.state.claimedAchievements.contains(lhs.id)
            let rhsClaimable = Achievements.isComplete(rhs, state: engine.state)
                && !engine.state.claimedAchievements.contains(rhs.id)
            return lhsClaimable && !rhsClaimable
        }
    }

    var body: some View {
        if engine.claimableAchievements.count > 1 {
            IntroBanner(key: IntroKey.claimAllAchievements, symbol: "checkmark.circle.fill",
                        title: "Claim everything at once",
                        detail: "When more than one achievement is ready, this collects them all in a single tap instead of one at a time.")
            claimAllButton
        }
        ForEach(sortedSpecs) { spec in
            row(spec)
        }
    }

    private var claimAllButton: some View {
        Button {
            let claimed = engine.claimAllAchievements()
            guard claimed > 0 else { return }
            Haptics.success()
            sound.play(.bigReward)
            onToast("Claimed \(Format.plural(claimed, "achievement"))")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Claim All (\(engine.claimableAchievements.count))")
            }
            .font(Theme.body(13, weight: .black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.positive, shadow: Theme.positive.opacity(0.5), radius: 12))
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
