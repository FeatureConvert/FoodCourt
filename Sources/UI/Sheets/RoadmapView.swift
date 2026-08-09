import SwiftUI

/// A single read-only ladder plotting progress that otherwise lives scattered across four
/// different sheets, so there is always one place that answers "what's next?" No new
/// persisted state - every row reads straight off state that already exists elsewhere.
struct RoadmapSection: View {
    @EnvironmentObject private var engine: GameEngine

    private struct Item: Identifiable {
        let id: String
        let title: String
        let detail: String
        let done: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Venues", items: venueItems)
            group("League", items: leagueItems)
            group("Research", items: researchItems)
            group("Prestige", items: prestigeItems)
            group("Legacy", items: legacyItems)
        }
    }

    private var venueItems: [Item] {
        Balance.venues.map { venue in
            let unlocked = engine.state.venues[venue.id].unlocked
            return Item(id: "venue-\(venue.id)", title: venue.name,
                       detail: unlocked ? "Open" : "Locked", done: unlocked)
        }
    }

    private var leagueItems: [Item] {
        LeagueTier.allCases.map { tier in
            Item(id: "league-\(tier.rawValue)", title: "\(tier.name) league",
                detail: "Reach the \(tier.name) tier",
                done: engine.state.bestLeagueTierReached.rawValue >= tier.rawValue)
        }
    }

    private var researchItems: [Item] {
        ResearchBranch.allCases.map { branch in
            let nodes = Research.nodes(in: branch)
            let ranks = nodes.reduce(0) { $0 + (engine.state.research[$1.id] ?? 0) }
            let maxRanks = nodes.reduce(0) { $0 + $1.maxRank }
            return Item(id: "branch-\(branch.id)", title: "\(branch.title) branch maxed",
                       detail: "\(ranks) / \(maxRanks) ranks", done: ranks >= maxRanks)
        }
    }

    private var prestigeItems: [Item] {
        [1, 5, 15, 30].map { n in
            Item(id: "prestige-\(n)", title: "Prestige \(n)×",
                detail: "\(engine.state.prestigeCount) / \(n)",
                done: engine.state.prestigeCount >= n)
        }
    }

    private var legacyItems: [Item] {
        let level = engine.state.legacy.level
        return [
            Item(id: "legacy-unlock", title: "Unlock Legacy",
                detail: "\(engine.state.prestigeCount) / \(Balance.legacyUnlockPrestigeCount) franchises",
                done: engine.canLegacyReset || level > 0),
            Item(id: "legacy-1", title: "Reach Legacy 1", detail: "Level \(level) / 1", done: level >= 1),
            Item(id: "legacy-3", title: "Reach Legacy 3", detail: "Level \(level) / 3", done: level >= 3),
        ]
    }

    private func group(_ title: String, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.body(11, weight: .black))
                .foregroundStyle(Theme.textDim)
            ForEach(items) { row($0) }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(item.done ? Theme.positive : Theme.textDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(item.detail)
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .panel(item.done ? Theme.panelRaised : Theme.panel)
    }
}
