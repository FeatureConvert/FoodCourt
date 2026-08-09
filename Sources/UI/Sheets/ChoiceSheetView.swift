import SwiftUI

/// The Franchise Contract picker, shown once per run right after a reset. Mirrors
/// PerkChoiceView's anatomy exactly - IntroBanner primer, three chunky option rows,
/// confetti on pick, dismissal beat - because the player already knows how that sheet
/// works, and a familiar shape is its own tutorial.
struct ContractChoiceView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    @Environment(\.dismiss) private var dismiss
    let onToast: (String) -> Void

    @State private var celebratingID: String?

    var body: some View {
        SheetScaffold(title: "Franchise Contract",
                      subtitle: "Pick one - it shapes this whole run") {
            IntroBanner(key: IntroKey.contracts, symbol: "doc.text.fill",
                        title: "What's a Contract?",
                        detail: "Every Franchise, choose how the next run plays: each contract trades one strength for one weakness, and Play It Straight is always available. It lasts until your next reset - nothing here is permanent.")

            if let offer = engine.pendingContractOffer {
                ForEach(offer) { contract in
                    optionRow(contract)
                }
            }

            Text("A new set of contracts is offered after every Franchise.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled(true)
    }

    private func optionRow(_ contract: FranchiseContract) -> some View {
        Button {
            engine.chooseContract(contract.id)
            Haptics.success()
            sound.play(.reward)
            onToast("Contract signed: \(contract.title)")
            celebratingID = contract.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { dismiss() }
        } label: {
            HStack(spacing: 12) {
                GlyphIcon(contract.symbol, tint: Theme.star)
                    .frame(width: 22, height: 22)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(contract.title)
                        .font(Theme.body(14, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text(contract.detail)
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(contract.id == "straight" ? Theme.textDim : Theme.positive)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
        .overlay {
            if celebratingID == contract.id { ConfettiBurstView() }
        }
    }
}

/// The Legacy tree picker - one permanent perk per Legacy level, same familiar shape.
struct LegacyPerkChoiceView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    @Environment(\.dismiss) private var dismiss
    let onToast: (String) -> Void

    @State private var celebratingID: String?

    var body: some View {
        SheetScaffold(title: "Legacy Perk",
                      subtitle: "Level \(engine.state.legacy.level) - pick one, it's forever") {
            IntroBanner(key: IntroKey.legacyTree, symbol: "tree.fill",
                        title: "The Legacy tree",
                        detail: "Every Legacy level grants its +20% profit AND one permanent perk of your choice. Picks stack across Legacies and never reset - this is what makes your empire's legacy yours.")

            if let offer = engine.pendingLegacyPerkOffer {
                ForEach(offer) { perk in
                    optionRow(perk)
                }
            }

            Text("Perks already taken: \(takenSummary)")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled(true)
    }

    private var takenSummary: String {
        let taken = engine.state.legacyPerks.filter { $0.value > 0 }
        guard !taken.isEmpty else { return "none yet" }
        return taken.compactMap { id, stacks in
            LegacyTree.perk(id).map { "\($0.title)\(stacks > 1 ? " ×\(stacks)" : "")" }
        }.sorted().joined(separator: " · ")
    }

    private func optionRow(_ perk: LegacyPerk) -> some View {
        let stacks = engine.state.legacyPerks[perk.id] ?? 0
        return Button {
            engine.chooseLegacyPerk(perk.id)
            Haptics.success()
            sound.play(.bigReward)
            onToast("Legacy perk: \(perk.title)")
            celebratingID = perk.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { dismiss() }
        } label: {
            HStack(spacing: 12) {
                GlyphIcon(perk.symbol, tint: Theme.gem)
                    .frame(width: 22, height: 22)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(perk.title)
                            .font(Theme.body(14, weight: .black))
                            .foregroundStyle(Theme.text)
                        if stacks > 0 {
                            Text("owned ×\(stacks)")
                                .font(Theme.body(9, weight: .black))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.gem))
                        }
                    }
                    Text(perk.detail)
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.positive)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
        .overlay {
            if celebratingID == perk.id { ConfettiBurstView() }
        }
    }
}
