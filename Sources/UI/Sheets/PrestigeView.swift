import SwiftUI

struct PrestigeView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case franchise, research, roadmap
        var id: String { rawValue }
        var title: String {
            switch self {
            case .franchise: return "Franchise"
            case .research: return "Research"
            case .roadmap: return "Map"
            }
        }
    }

    @State private var tab: Tab = .franchise

    var body: some View {
        SheetScaffold(title: "Franchise", subtitle: subtitle) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            switch tab {
            case .franchise: FranchiseSection(onToast: onToast)
            case .research: ResearchSection(onToast: onToast)
            case .roadmap: RoadmapSection()
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case .franchise: return "Sell up, start again, keep the multiplier"
        case .research: return "\(Format.count(engine.state.stars)) stars to spend"
        case .roadmap: return "Everything you're working toward, in one place"
        }
    }
}

// MARK: - Franchise

private struct FranchiseSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    @Environment(\.dismiss) private var dismiss
    let onToast: (String) -> Void

    @State private var confirming = false

    var body: some View {
        VStack(spacing: 10) {
            StarIcon().frame(width: 64, height: 64)
            Text("+\(Format.count(engine.pendingStars))")
                .font(Theme.numeric(38))
                .foregroundStyle(Theme.star)
            Text("Franchise Stars waiting")
                .font(Theme.body(13, weight: .bold))
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .panel(Theme.panel)

        VStack(spacing: 0) {
            statRow("Stars to spend", Format.count(engine.state.stars))
            divider
            statRow("Stars ever earned", Format.count(engine.state.lifetimeStars))
            divider
            statRow("Profit bonus now",
                    "+\(Int((Balance.starMultiplier(stars: engine.state.lifetimeStars) - 1) * 100))%")
            divider
            statRow("Profit bonus after",
                    "+\(Int((Balance.starMultiplier(stars: engine.state.lifetimeStars + engine.pendingStars) - 1) * 100))%",
                    highlight: engine.pendingStars > 0)
            divider
            statRow("Lifetime earnings", Format.currency(engine.state.lifetimeEarnings))
            divider
            statRow("This run", Format.currency(engine.state.runEarnings))
        }
        .panel(Theme.panel)

        VStack(alignment: .leading, spacing: 6) {
            bullet("Every station, level, and manager placement resets", system: "arrow.counterclockwise")
            bullet("Coins reset to zero, venues close except the first", system: "building.2.fill")
            bullet("Coin-hired staff is let go - gem, IAP, and reward staff stays",
                   system: "person.fill.checkmark")
            bullet("Recipes and research are kept", system: "checkmark.seal.fill", good: true)
            bullet("More stars mean a bigger permanent profit bonus, forever", system: "star.fill", good: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel(Theme.panel)

        Button {
            if confirming {
                let awarded = engine.prestige()
                Haptics.success()
                sound.play(.bigReward)
                onToast("Franchised out for \(awarded) stars")
                dismiss()
            } else {
                confirming = true
            }
        } label: {
            Text(buttonTitle)
                .font(Theme.body(16, weight: .black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: engine.canPrestige ? (confirming ? Theme.negative : Theme.star) : Theme.locked,
            shadow: Theme.ink,
            disabled: !engine.canPrestige
        ))
        .disabled(!engine.canPrestige)

        if !engine.canPrestige {
            Text("Earn \(Format.currency(Balance.minimumLifetimeForPrestige)) lifetime to unlock your first franchise.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }

        if engine.canLegacyReset { legacyCard }
    }

    // MARK: Legacy

    @State private var confirmingLegacy = false

    private var legacyCard: some View {
        VStack(spacing: 10) {
            Text("LEGACY")
                .font(Theme.body(11, weight: .black))
                .foregroundStyle(Theme.textDim)

            Text("Level \(engine.state.legacy.level) → \(engine.state.legacy.level + 1)")
                .font(Theme.numeric(20))
                .foregroundStyle(Theme.text)

            Text("Give up your \(Int((Balance.starMultiplier(stars: engine.state.lifetimeStars) - 1) * 100))% star bonus and every research rank, permanently, for +\(Int(Balance.legacyMultiplier(level: 1) * 100 - 100))% more forever.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            Button {
                if confirmingLegacy {
                    let level = engine.legacyReset()
                    Haptics.success()
                    sound.play(.bigReward)
                    onToast("Legacy Level \(level)")
                    confirmingLegacy = false
                    dismiss()
                } else {
                    confirmingLegacy = true
                }
            } label: {
                Text(confirmingLegacy ? "Tap again to confirm" : "Start a new Legacy")
                    .font(Theme.body(14, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(ChunkyButtonStyle(fill: confirmingLegacy ? Theme.negative : Theme.gemDeep,
                                           shadow: Theme.ink))
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .panel(Theme.panelRaised)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.star, lineWidth: 1.5))
    }

    private var buttonTitle: String {
        guard engine.canPrestige else { return "Not ready yet" }
        return confirming ? "Tap again to confirm" : "Franchise for \(engine.pendingStars) stars"
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke.opacity(0.5)).frame(height: 1).padding(.horizontal, 14)
    }

    private func statRow(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(value)
                .font(Theme.numeric(14))
                .foregroundStyle(highlight ? Theme.star : Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func bullet(_ text: String, system: String, good: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(good ? Theme.positive : Theme.textDim)
                .frame(width: 18)
            Text(text)
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Research

private struct ResearchSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void

    var body: some View {
        IntroBanner(key: IntroKey.research, symbol: "flask.fill",
                    title: "Research is a second thing to spend stars on",
                    detail: "Every star also counts toward your permanent profit bonus, whether you spend it here or not - so buying research never costs you that bonus. Ranks unlock top to bottom within a branch.")

        HStack(spacing: 10) {
            StarIcon().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Format.count(engine.state.stars)) stars to spend")
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(Theme.text)
                Text("Earned by franchising. Research is permanent.")
                    .font(Theme.body(10, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
        }
        .padding(12)
        .panel(Theme.panel)

        ForEach(ResearchBranch.allCases) { branch in
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(branch.title.uppercased())
                        .font(Theme.body(12, weight: .black))
                        .foregroundStyle(Theme.coin)
                    Text(branch.blurb)
                        .font(Theme.body(10, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                ForEach(Research.nodes(in: branch)) { node in
                    nodeRow(node)
                }
            }
            .padding(12)
            .panel(Theme.panel)
        }
    }

    private func nodeRow(_ node: ResearchNode) -> some View {
        let rank = engine.researchRank(node.id)
        let unlocked = Research.isUnlocked(node, ranks: engine.state.research)
        let maxed = rank >= node.maxRank
        let cost = node.cost(forRank: rank)
        let affordable = engine.canBuyResearch(node)

        return Button {
            if engine.buyResearch(node) {
                Haptics.success()
                sound.play(.reward)
                onToast("\(node.title) → rank \(rank + 1)")
            } else if !unlocked {
                sound.play(.denied)
                onToast("Unlock the node above it first")
            } else if !maxed {
                sound.play(.denied)
                onToast("Need \(cost) stars")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: node.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(unlocked ? Theme.text : Theme.locked)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(unlocked ? Theme.text : Theme.textDim)
                    Text(node.detail)
                        .font(Theme.body(10, weight: .bold))
                        .foregroundStyle(Theme.positive)
                    rankPips(rank: rank, max: node.maxRank)
                }
                Spacer(minLength: 0)

                if maxed {
                    Text("MAX")
                        .font(Theme.body(11, weight: .black))
                        .foregroundStyle(Theme.positive)
                } else {
                    HStack(spacing: 3) {
                        StarIcon().frame(width: 13, height: 13)
                        Text("\(cost)")
                            .font(Theme.numeric(13))
                            .foregroundStyle(affordable ? Theme.ink : Theme.textDim)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Capsule().fill(affordable ? Theme.star : Theme.ink.opacity(0.5)))
                }
            }
            .padding(10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink,
                                       disabled: !unlocked, radius: 12))
        .disabled(maxed)
    }

    private func rankPips(rank: Int, max: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<max, id: \.self) { index in
                Capsule()
                    .fill(index < rank ? Theme.coin : Theme.stroke)
                    .frame(width: 9, height: 4)
            }
        }
    }
}
