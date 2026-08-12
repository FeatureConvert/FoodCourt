import SwiftUI

struct EventsView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case daily, festival, league
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: return "Daily"
            case .festival: return "Festival"
            case .league: return "League"
            }
        }
    }

    @State private var tab: Tab

    init(initialTab: Tab = .daily, onToast: @escaping (String) -> Void) {
        _tab = State(initialValue: initialTab)
        self.onToast = onToast
    }

    var body: some View {
        SheetScaffold(title: "Events", subtitle: subtitle) {
            SegmentedTabs(selection: $tab) { $0.title }
                .padding(.bottom, 4)

            switch tab {
            case .daily: DailyRewardSection(onToast: onToast)
            case .festival: FestivalSection(onToast: onToast)
            case .league: LeagueSection()
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case .daily:
            return engine.dailyAvailable ? "A reward is waiting" : "Come back tomorrow"
        case .festival:
            return "\(Festival.seasonName) — \(Format.duration(Festival.timeRemaining(engine.state.festival, now: engine.state.now))) left"
        case .league:
            return "\(engine.state.league.tier.name) league — \(Format.duration(League.timeRemaining(engine.state.league, now: engine.state.now))) left"
        }
    }
}

// MARK: - Festival

private struct FestivalSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void

    private var festival: FestivalState { engine.state.festival }

    var body: some View {
        IntroBanner(key: IntroKey.festival, symbol: "ticket.fill",
                    title: "Seasonal, and free to fully clear",
                    detail: "Tickets from playing unlock every tier on this track before the season ends. A Premium Pass just adds a second reward alongside each one - it never gates anything the free track already has.")

        // Paced: the Gauntlet is a veteran mode; a first-week player sees a calmer Events.
        if engine.gauntletRelevant {
            gauntletCard
        }

        header

        seasonTwistCard

        if !engine.festivalPremiumActive {
            premiumPitch
        }

        if unclaimedCount > 1 {
            IntroBanner(key: IntroKey.claimAllFestivalIntro, symbol: "checkmark.circle.fill",
                        title: "Claim everything at once",
                        detail: "When more than one festival tier is ready, this collects them all in a single tap instead of one at a time.")
            claimAllButton
        }

        ForEach(Festival.allTiers) { tier in
            tierRow(tier)
        }
    }

    private var unclaimedCount: Int {
        Festival.unclaimedCount(festival, premiumActive: engine.festivalPremiumActive)
    }

    /// A returning player can find several tiers unlocked across both tracks at once - up
    /// to 60 individual taps otherwise, at 30 tiers x free/premium.
    private var claimAllButton: some View {
        Button {
            let claimed = engine.claimAllFestival()
            guard claimed > 0 else { return }
            Haptics.success()
            sound.play(.bigReward)
            onToast("Claimed \(Format.plural(claimed, "reward"))")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Claim All (\(unclaimedCount))")
            }
            .font(Theme.body(13, weight: .black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.positive, shadow: Theme.positive.opacity(0.5), radius: 12))
    }

    /// This season's rotating gameplay twist, with the same first-open explainer treatment
    /// every other system gets.
    @ViewBuilder private var seasonTwistCard: some View {
        let twist = Festival.modifier(seasonID: festival.seasonID)
        IntroBanner(key: IntroKey.seasonTwist, symbol: "wand.and.stars",
                    title: "Every season plays differently",
                    detail: "Each carnival season carries one twist - extra tickets from tapping, richer offline hauls, doubled VIP odds. It changes every week, so check back here when a new season starts.",
                    gate: engine.seasonTwistRelevant)
        HStack(spacing: 10) {
            GlyphIcon("wand.and.stars", tint: Theme.gem)
                .frame(width: 20, height: 20)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.ink.opacity(0.5)))
            VStack(alignment: .leading, spacing: 2) {
                Text("SEASON \(festival.seasonID) TWIST · \(twist.title.uppercased())")
                    .font(Theme.body(10, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(Theme.gem)
                Text(twist.detail)
                    .font(Theme.body(12, weight: .bold))
                    .foregroundStyle(Theme.text)
                if engine.state.bestFestivalTier > 0 {
                    Text("Personal best: Tier \(engine.state.bestFestivalTier)")
                        .font(Theme.body(10, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .panel(Theme.panelRaised)
    }

    /// The Weekly Gauntlet card, shown above the festival track - once a week, the
    /// ten-minute sprint is the loudest thing in Events until it's been run.
    @ViewBuilder var gauntletCard: some View {
        IntroBanner(key: IntroKey.gauntlet, symbol: "stopwatch.fill",
                    title: "The Weekly Gauntlet",
                    detail: "Once a week: a ten-minute scored sprint on your live board under a rotating twist. Score every coin you can - taps, combos, boosts, Rush, everything counts - and beat your idle baseline for a gem purse. Personal bests are forever.")
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GlyphIcon("stopwatch.fill", tint: Theme.negative)
                    .frame(width: 20, height: 20)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEKLY GAUNTLET · \(engine.gauntletMutator.title.uppercased())")
                        .font(Theme.body(10, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(Theme.negative)
                    Text(engine.gauntletMutator.detail)
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if engine.state.gauntletBestEver > 0 {
                        Text("Best ever: \(Format.currency(engine.state.gauntletBestEver))")
                            .font(Theme.body(10, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Spacer(minLength: 0)
            }
            if engine.gauntletActive {
                HStack {
                    Text("SPRINTING · \(Format.currency(engine.state.gauntletScore))")
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.positive)
                    Spacer()
                    Text(Format.duration((engine.state.gauntletEndsAt ?? engine.state.now).timeIntervalSince(engine.state.now)))
                        .font(Theme.numeric(13))
                        .foregroundStyle(Theme.negative)
                }
            } else if engine.gauntletPlayedThisWeek {
                Text("Run for this week - a new twist arrives Monday.")
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            } else {
                Button {
                    if engine.startGauntlet() {
                        Haptics.thud()
                        sound.play(.bigReward)
                        onToast("GAUNTLET! Ten minutes - earn everything you can!")
                    }
                } label: {
                    Text("Start the sprint")
                        .font(Theme.body(14, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.negative, shadow: Theme.ink))
            }
        }
        .padding(12)
        .panel(Theme.panelRaised)
    }

    private var header: some View {
        let progress = Festival.progressToNextTier(tickets: festival.tickets)
        return VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Festival.seasonName.uppercased())
                        .font(Theme.body(12, weight: .black))
                        .foregroundStyle(Theme.coin)
                    Text("Tier \(progress.current) of \(Festival.tierCount)")
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        TicketIcon()
                            .frame(width: 16, height: 16)
                        Text(Format.count(festival.tickets))
                            .font(Theme.numeric(16))
                            .foregroundStyle(Theme.text)
                    }
                    Text("tickets")
                        .font(Theme.body(10, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.7))
                    Capsule().fill(Theme.coin)
                        .frame(width: geo.size.width * progress.fraction)
                }
            }
            .frame(height: 7)

            Text("Earn tickets by serving, finishing goals, claiming dailies, and running Rush Hours.")
                .font(Theme.body(10, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .panel(Theme.panel)
    }

    private func purchasePremiumPass() {
        guard let item = ShopCatalog.item(for: Festival.premiumProductID) else { return }
        Task { await store.purchase(item) }
    }

    private var premiumPitch: some View {
        let item = ShopCatalog.item(for: Festival.premiumProductID)
        return Button(action: purchasePremiumPass) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.ink.opacity(0.18))
                    CrownIcon()
                        .frame(width: 26, height: 26)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("PREMIUM PASS")
                        .font(Theme.body(9, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(Theme.ink.opacity(0.6))
                    Text("Carnival Pass")
                        .font(Theme.body(15, weight: .black))
                        .foregroundStyle(Theme.ink)
                    Text("Unlocks a second, bigger reward on all 30 tiers")
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.75))
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(item.map { store.displayPrice(for: $0) } ?? "$3.99")
                    .font(Theme.numeric(15))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.ink))
            }
            .padding(13)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.coin, shadow: Theme.coinDeep, radius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.star, lineWidth: 2)
        )
        .shadow(color: Theme.coin.opacity(0.45), radius: 14, y: 4)
    }

    private func tierRow(_ tier: FestivalTier) -> some View {
        let reached = festival.tickets >= tier.ticketsRequired
        let premiumActive = engine.festivalPremiumActive
        let freeClaimable = Festival.canClaim(festival, tier: tier.index, premium: false,
                                              premiumActive: premiumActive)
        let premiumClaimable = Festival.canClaim(festival, tier: tier.index, premium: true,
                                                 premiumActive: premiumActive)

        return HStack(spacing: 10) {
            VStack(spacing: 1) {
                Text("\(tier.index)")
                    .font(Theme.numeric(15))
                    .foregroundStyle(reached ? Theme.coin : Theme.textDim)
                Text(Format.count(tier.ticketsRequired))
                    .font(Theme.body(8, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .frame(width: 40)

            rewardChip(tier.free, claimable: freeClaimable,
                       claimed: festival.claimedFree.contains(tier.index),
                       locked: !reached, premium: false) {
                claim(tier: tier.index, premium: false)
            }

            // A tier the player has actually reached but can't claim without the pass is the
            // single most persuasive moment to pitch it - tapping it goes straight to
            // purchase instead of just sitting there disabled and unexplained.
            let needsPass = reached && !premiumActive
            rewardChip(tier.premium, claimable: premiumClaimable,
                       claimed: festival.claimedPremium.contains(tier.index),
                       locked: !reached || !premiumActive, premium: true,
                       needsPass: needsPass) {
                if needsPass { purchasePremiumPass() } else { claim(tier: tier.index, premium: true) }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .panel(reached ? Theme.panel : Theme.panel.opacity(0.5), radius: 12)
    }

    private func rewardChip(_ reward: FestivalReward, claimable: Bool, claimed: Bool,
                            locked: Bool, premium: Bool, needsPass: Bool = false,
                            action: @escaping () -> Void) -> some View {
        let tint = chipForeground(claimable: claimable, claimed: claimed, locked: locked)
        return Button(action: action) {
            HStack(spacing: 6) {
                if claimed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                } else {
                    GlyphIcon(reward.symbol, tint: tint)
                        .frame(width: 13, height: 13)
                }
                Text(reward.label)
                    .font(Theme.body(10, weight: .black))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(claimable ? (premium ? Theme.star : Theme.positive) : Theme.ink.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(needsPass ? Theme.star : (premium ? Theme.star.opacity(0.6) : Theme.stroke),
                                   lineWidth: needsPass ? 1.5 : 1.2)
                    )
            )
            .overlay(alignment: .topTrailing) {
                if needsPass {
                    CrownIcon()
                        .frame(width: 15, height: 15)
                        .padding(3)
                        .background(Circle().fill(Theme.ink))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!claimable && !needsPass)
    }

    private func chipForeground(claimable: Bool, claimed: Bool, locked: Bool) -> Color {
        if claimable { return Theme.ink }
        if claimed { return Theme.positive }
        return locked ? Theme.textDim : Theme.text
    }

    private func claim(tier: Int, premium: Bool) {
        guard let reward = engine.claimFestival(tier: tier, premium: premium) else { return }
        Haptics.success()
        sound.play(.reward)
        onToast("Tier \(tier): \(reward.label)")
    }
}

// MARK: - League

private struct LeagueSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var gameCenter: GameCenterService
    @State private var showingGameCenter = false

    var body: some View {
        let league = engine.state.league
        let standings = League.standings(league)
        let rank = League.playerRank(league)

        IntroBanner(key: IntroKey.league, symbol: "trophy.fill",
                    title: "A weekly race, not a fight",
                    detail: "Your rivals earn based on how fast you're earning, so climbing is really about growing your own income. Finish top 7 to promote a tier for bigger rewards; finish in the bottom 7 and you drop one.")

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: league.tier.hex).opacity(0.25))
                    Circle().stroke(Color(hex: league.tier.hex), lineWidth: 2.5)
                    TrophyIcon(cup: Color(hex: league.tier.hex),
                               base: Color(hex: league.tier.hex).opacity(0.75))
                        .frame(width: 30, height: 30)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(league.tier.name) League")
                        .font(Theme.body(15, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text("Currently #\(rank) of \(League.size)")
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(rank <= League.promoteCount ? Theme.positive : Theme.textDim)
                    Text("Ends in \(Format.duration(League.timeRemaining(league, now: engine.state.now)))")
                        .font(Theme.body(10, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                legend(color: Theme.positive, text: "Top \(League.promoteCount) promote")
                legend(color: Theme.negative, text: "Bottom \(League.relegateCount) relegate")
            }
        }
        .padding(12)
        .panel(Theme.panel)

        VStack(spacing: 0) {
            ForEach(standings) { entry in
                row(entry)
                if entry.rank != League.size {
                    Rectangle().fill(Theme.stroke.opacity(0.35)).frame(height: 1)
                }
            }
        }
        .panel(Theme.panel)

        Text("A solo ladder: your rivals are simulated, and their pace is set by your own income so it stays competitive as you grow.")
            .font(Theme.body(11, weight: .medium))
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

        if gameCenter.isAuthenticated {
            Button {
                gameCenter.reportLifetimeEarnings(engine.state.lifetimeEarnings)
                showingGameCenter = true
            } label: {
                HStack(spacing: 8) {
                    TrophyIcon().frame(width: 16, height: 16)
                    Text("Global Leaderboard")
                }
                .font(Theme.body(13, weight: .black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
            .sheet(isPresented: $showingGameCenter) { GameCenterView() }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(Theme.body(9, weight: .bold))
                .foregroundStyle(Theme.textDim)
        }
    }

    private func row(_ entry: LeagueEntry) -> some View {
        let promoting = entry.rank <= League.promoteCount
        let relegating = entry.rank > League.size - League.relegateCount

        return HStack(spacing: 10) {
            ZStack {
                if promoting { Circle().fill(Theme.positive.opacity(0.25)) }
                else if relegating { Circle().fill(Theme.negative.opacity(0.22)) }
                Text("\(entry.rank)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(promoting ? Theme.positive : (relegating ? Theme.negative : Theme.textDim))
            }
            .frame(width: 28, height: 28)

            Text(entry.name)
                .font(Theme.body(12, weight: entry.isPlayer ? .black : .semibold))
                .foregroundStyle(entry.isPlayer ? Theme.coin : Theme.text)
                .lineLimit(1)
            if entry.isNemesis {
                Text("RIVAL")
                    .font(Theme.body(8, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.negative))
            }

            Spacer(minLength: 0)

            Text(Format.currency(entry.score))
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(entry.isPlayer ? Theme.coin.opacity(0.1) : .clear)
    }
}
