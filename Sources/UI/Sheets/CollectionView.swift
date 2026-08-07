import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case staff, recipes
        var id: String { rawValue }
        var title: String { self == .staff ? "Staff" : "Recipes" }
    }

    @State private var tab: Tab = .staff

    var body: some View {
        SheetScaffold(title: "Collection", subtitle: subtitle) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            switch tab {
            case .staff: StaffSection(onToast: onToast)
            case .recipes: RecipeSection()
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case .staff:
            return "\(engine.state.assignedManagerCount) working · \(engine.state.unassignedManagers.count) on the bench"
        case .recipes:
            return "\(Recipes.totalCollected(engine.state.recipeCards)) of \(Balance.venues.count * 6) cards found"
        }
    }
}

// MARK: - Staff

private struct StaffSection: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    var body: some View {
        if engine.state.managers.isEmpty {
            emptyState
        } else {
            ForEach(sortedManagers) { manager in
                row(manager)
            }
        }
    }

    /// Best staff first - the player cares about their legendaries, not their trainees.
    private var sortedManagers: [OwnedManager] {
        engine.state.managers.sorted { a, b in
            if a.spec.rarity != b.spec.rarity { return a.spec.rarity > b.spec.rarity }
            return a.spec.name < b.spec.name
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textDim)
            Text("No staff yet")
                .font(Theme.body(14, weight: .black))
                .foregroundStyle(Theme.text)
            Text("Hire from a station card, or earn better staff from goals, the festival, and the league.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .panel(Theme.panel)
    }

    private func row(_ manager: OwnedManager) -> some View {
        let spec = manager.spec
        let placement = engine.state.assignment(of: manager.id)
        let rarity = rarityColor(spec.rarity)

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(rarity.opacity(0.22))
                Circle().stroke(rarity, lineWidth: 2)
                CustomerSprite(seed: spec.portraitSeed)
                    .frame(width: 30, height: 42)
                    .offset(y: 3)
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name)
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(Theme.text)
                Text(spec.trait.detail)
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.positive)
                Text(spec.rarity.label)
                    .font(Theme.body(9, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(rarity))
            }
            Spacer(minLength: 0)

            Menu {
                ForEach(assignableStations, id: \.self) { index in
                    Button(Balance.venue(engine.state.currentVenue).stations[index].name) {
                        engine.assign(managerID: manager.id,
                                      venue: engine.state.currentVenue, station: index)
                        Haptics.success()
                        onToast("\(spec.name) → \(Balance.venue(engine.state.currentVenue).stations[index].name)")
                    }
                }
                if placement != nil {
                    Divider()
                    Button("Send to bench", role: .destructive) {
                        if let placement {
                            engine.assign(managerID: nil, venue: placement.venue, station: placement.station)
                            onToast("\(spec.name) is on the bench")
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: placement == nil ? "plus.circle.fill" : "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(placementLabel(placement))
                        .font(Theme.body(9, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(placement == nil ? Theme.coin : Theme.textDim)
                .frame(width: 74, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.panelRaised))
            }
        }
        .padding(12)
        .panel(Theme.panel)
    }

    private var assignableStations: [Int] {
        let venue = engine.state.currentVenue
        return Balance.venue(venue).stations
            .filter { engine.state.venues[venue].stations[$0.id].isOwned }
            .map(\.id)
    }

    private func placementLabel(_ placement: (venue: Int, station: Int)?) -> String {
        guard let placement else { return "Assign" }
        return Balance.venue(placement.venue).stations[placement.station].name
    }

    private func rarityColor(_ rarity: ManagerRarity) -> Color {
        switch rarity {
        case .common: return Theme.textDim
        case .rare: return Theme.gem
        case .epic: return Color(hex: "#B07BE8")
        case .legendary: return Theme.star
        }
    }
}

// MARK: - Recipes

private struct RecipeSection: View {
    @EnvironmentObject private var engine: GameEngine

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ForEach(Balance.venues) { venue in
            let unlocked = engine.state.venues[venue.id].unlocked
            let complete = Recipes.isSetComplete(engine.state.recipeCards, venue: venue.id)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(venue.name)
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if complete {
                        Text("SET +\(Int(Recipes.setBonus * 100))%")
                            .font(Theme.body(10, weight: .black))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.positive))
                    } else {
                        Text("\(Recipes.collected(engine.state.recipeCards, venue: venue.id))/6")
                            .font(Theme.body(11, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(venue.stations) { spec in
                        card(venue: venue, spec: spec)
                    }
                }
            }
            .padding(12)
            .panel(unlocked ? Theme.panel : Theme.panel.opacity(0.55))
        }

        Text("Cards drop when you level a station up. Duplicates add a star; a full venue set pays +\(Int(Recipes.setBonus * 100))% on that venue.")
            .font(Theme.body(11, weight: .medium))
            .foregroundStyle(Theme.textDim)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    private func card(venue: VenueSpec, spec: StationSpec) -> some View {
        let stars = Recipes.stars(engine.state.recipeCards, venue: venue.id, station: spec.id)
        let owned = stars > 0

        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(owned ? Theme.ink.opacity(0.55) : Theme.ink.opacity(0.3))
                FoodSprite(art: spec.art, colors: spec.colors)
                    .frame(width: 40, height: 40)
                    .saturation(owned ? 1 : 0)
                    .opacity(owned ? 1 : 0.25)
                if !owned {
                    Image(systemName: "questionmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .frame(height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(owned ? Theme.star.opacity(0.7) : Theme.stroke, lineWidth: 1.5)
            )

            HStack(spacing: 1) {
                ForEach(0..<Recipes.maxStars, id: \.self) { index in
                    Image(systemName: index < stars ? "star.fill" : "star")
                        .font(.system(size: 7))
                        .foregroundStyle(index < stars ? Theme.star : Theme.stroke)
                }
            }
        }
    }
}
