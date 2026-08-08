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
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
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
    let onToast: (String) -> Void

    private var festival: FestivalState { engine.state.festival }

    var body: some View {
        header

        if !engine.festivalPremiumActive {
            premiumPitch
        }

        ForEach(Festival.allTiers) { tier in
            tierRow(tier)
        }
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
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.coin)
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

    private var premiumPitch: some View {
        let item = ShopCatalog.item(for: Festival.premiumProductID)
        return Button {
            if let item { Task { await store.purchase(item) } }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carnival Pass")
                        .font(Theme.body(14, weight: .black))
                        .foregroundStyle(Theme.ink)
                    Text("Unlocks the premium reward on all 30 tiers")
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.75))
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(item.map { store.displayPrice(for: $0) } ?? "$3.99")
                    .font(Theme.numeric(14))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.ink))
            }
            .padding(12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.coin, shadow: Theme.coinDeep))
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

            rewardChip(tier.premium, claimable: premiumClaimable,
                       claimed: festival.claimedPremium.contains(tier.index),
                       locked: !reached || !premiumActive, premium: true) {
                claim(tier: tier.index, premium: true)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .panel(reached ? Theme.panel : Theme.panel.opacity(0.5), radius: 12)
    }

    private func rewardChip(_ reward: FestivalReward, claimable: Bool, claimed: Bool,
                            locked: Bool, premium: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: claimed ? "checkmark.circle.fill" : reward.symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(reward.label)
                    .font(Theme.body(10, weight: .black))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }
            .foregroundStyle(chipForeground(claimable: claimable, claimed: claimed, locked: locked))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(claimable ? (premium ? Theme.star : Theme.positive) : Theme.ink.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(premium ? Theme.star.opacity(0.6) : Theme.stroke, lineWidth: 1.2)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!claimable)
    }

    private func chipForeground(claimable: Bool, claimed: Bool, locked: Bool) -> Color {
        if claimable { return Theme.ink }
        if claimed { return Theme.positive }
        return locked ? Theme.textDim : Theme.text
    }

    private func claim(tier: Int, premium: Bool) {
        guard let reward = engine.claimFestival(tier: tier, premium: premium) else { return }
        Haptics.success()
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

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: league.tier.hex).opacity(0.25))
                    Circle().stroke(Color(hex: league.tier.hex), lineWidth: 2.5)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(Color(hex: league.tier.hex))
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
                    Image(systemName: "trophy.fill")
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
