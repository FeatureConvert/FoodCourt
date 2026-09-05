import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case staff, recipes, errands
        var id: String { rawValue }
        var title: String {
            switch self {
            case .staff: return "Staff"
            case .recipes: return "Recipes"
            case .errands: return "Errands"
            }
        }
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
            case .errands: ErrandsSection(onToast: onToast)
            }
        }
    }

    private var subtitle: String {
        switch tab {
        case .staff:
            return "\(engine.state.assignedManagerCount) working · \(engine.state.unassignedManagers.count) on the bench"
        case .recipes:
            return "\(Recipes.totalCollected(engine.state.recipeCards)) of \(Balance.venues.count * 6) cards found"
        case .errands:
            return "\(engine.state.errands.count) of \(Errands.maxSlots) slots busy"
        }
    }
}

// MARK: - Staff

private struct StaffSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void

    @State private var showChefConfetti = false

    var body: some View {
        IntroBanner(key: IntroKey.staff, symbol: "person.2.fill",
                    title: "Your whole roster, in one place",
                    detail: "A manager on a station automates it, even while the app is closed. Anyone on the bench isn't earning - assign them to a station, or send them on an Errand instead.")

        IntroBanner(key: IntroKey.guestChef, symbol: "star.circle.fill",
                    title: "The weekly Guest Chef",
                    detail: "A Legendary-tier hire rotates in every Monday, exclusive to this spot - no reward pool ever drops them. Buy with gems, keep forever, and next week someone new takes the stand.")
        guestChefBanner

        // Paced: the crew system stays invisible until the roster can actually form one.
        if engine.crewsRelevant {
            IntroBanner(key: IntroKey.synergies, symbol: "person.3.fill",
                        title: "Crews have chemistry",
                        detail: "Certain managers form a named crew: staff every member anywhere in the SAME venue and the whole venue earns a bonus. The crew list below shows who belongs together.")
            synergyBoard
        }

        if engine.autoAssignableCount > 0 {
            IntroBanner(key: IntroKey.autoAssignStaff, symbol: "checkmark.circle.fill",
                        title: "Fill open stations at once",
                        detail: "When a benched manager and an open station both exist, this staffs everything it can in one tap instead of assigning each by hand.")
            autoAssignButton
        }

        if engine.state.managers.isEmpty {
            emptyState
        } else {
            ForEach(sortedManagers) { manager in
                row(manager)
            }
        }
    }

    /// A player who just opened a new venue, or came back from a while away with several
    /// managers idle on the bench, otherwise has to drag each one to a station by hand.
    private var autoAssignButton: some View {
        Button {
            let assigned = engine.autoAssignBenchedManagers()
            guard assigned > 0 else { return }
            Haptics.success()
            sound.play(.reward)
            onToast("Assigned \(Format.plural(assigned, "manager"))")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill.checkmark")
                Text("Auto-Assign Bench (\(engine.autoAssignableCount))")
            }
            .font(Theme.body(13, weight: .black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.positive, shadow: Theme.positive.opacity(0.5), radius: 12))
    }

    /// Every crew, with its live status in the CURRENT venue - assembled crews glow, the
    /// rest read as a checklist of who to hunt for.
    private var synergyBoard: some View {
        let venue = engine.state.currentVenue
        let staffed = engine.state.staffedSpecIDs(venue: venue)
        return VStack(alignment: .leading, spacing: 8) {
            Text("CREWS · \(Balance.venue(venue).name.uppercased())")
                .font(Theme.body(10, weight: .black))
                .tracking(0.6)
                .foregroundStyle(Theme.textDim)
            ForEach(Synergies.all) { synergy in
                let active = synergy.memberIDs.allSatisfy(staffed.contains)
                HStack(spacing: 8) {
                    Image(systemName: active ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(active ? Theme.positive : Theme.textDim)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(synergy.title)
                            .font(Theme.body(12, weight: .black))
                            .foregroundStyle(active ? Theme.text : Theme.textDim)
                        Text(synergy.detail)
                            .font(Theme.body(10, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer(minLength: 0)
                    if active {
                        Text("ACTIVE")
                            .font(Theme.body(8, weight: .black))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.positive))
                    }
                }
            }
        }
        .padding(12)
        .panel(Theme.panel)
    }

    private var guestChefBanner: some View {
        let spec = engine.currentGuestChef
        let owned = engine.guestChefAlreadyPurchasedThisWeek

        return HStack(spacing: 12) {
            ZStack {
                ManagerRarityFrame(rarity: spec.rarity)
                CustomerSprite(seed: spec.portraitSeed)
                    .equatable()
                    .frame(width: 30, height: 42)
                    .offset(y: 3)
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // The portrait circle, "THIS WEEK" badge, and hire button are all
                    // rigid (fixed frame / .fixedSize()) by design - none of them should
                    // shrink. That means 100% of any width shortfall lands on this name
                    // alone, so its floor needs real headroom: 0.7 still truncated "Guest
                    // Chef Remy" on the narrowest supported phone (SE, 375pt).
                    Text(spec.name)
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .layoutPriority(1)
                    Text("THIS WEEK")
                        .font(Theme.body(9, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.star))
                        .fixedSize()
                }
                Text(spec.trait.detail)
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.positive)
            }
            Spacer(minLength: 0)

            Button {
                if let hired = engine.purchaseGuestChef() {
                    Haptics.success()
                    sound.play(.reward)
                    onToast("\(hired.name) joins your roster!")
                }
            } label: {
                if owned {
                    Text("Hired")
                        .font(Theme.body(12, weight: .black))
                        .frame(width: 74)
                        .padding(.vertical, 10)
                } else {
                    HStack(spacing: 3) {
                        GemIcon().frame(width: 12, height: 12)
                        Text("\(GuestChef.gemPrice)")
                    }
                    .font(Theme.numeric(13))
                    .frame(width: 74)
                    .padding(.vertical, 10)
                }
            }
            .buttonStyle(ChunkyButtonStyle(fill: owned ? Theme.locked : Theme.star,
                                           shadow: owned ? Theme.ink : Theme.star.opacity(0.5),
                                           disabled: owned))
            .disabled(owned)
        }
        .padding(12)
        .panel(Theme.panelRaised)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.star, lineWidth: 1.5))
        .overlay {
            if showChefConfetti { ConfettiBurstView() }
        }
        .onAppear {
            if engine.guestChefSpotlightPending {
                showChefConfetti = true
                engine.markGuestChefSpotlightSeen()
            }
        }
    }

    /// Best staff first - the player cares about their legendaries, not their trainees.
    private var sortedManagers: [OwnedManager] {
        let benched = Set(engine.state.unassignedManagers.map(\.id))
        return engine.state.managers.sorted { a, b in
            let aBenched = benched.contains(a.id), bBenched = benched.contains(b.id)
            if aBenched != bBenched { return aBenched && !bBenched }
            if a.spec.rarity != b.spec.rarity { return a.spec.rarity > b.spec.rarity }
            return a.name < b.name
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            PeopleIcon(tint: Theme.textDim)
                .frame(width: 30, height: 30)
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
                ManagerRarityFrame(rarity: spec.rarity)
                CustomerSprite(seed: spec.portraitSeed)
                    .equatable()
                    .frame(width: 30, height: 42)
                    .offset(y: 3)
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.name)
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
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
                        let placed = engine.assign(managerID: manager.id,
                                                    venue: engine.state.currentVenue, station: index)
                        guard placed else { return }
                        Haptics.success()
                        sound.play(.reward)
                        onToast("\(manager.name) → \(Balance.venue(engine.state.currentVenue).stations[index].name)")
                    }
                }
                if placement != nil {
                    Divider()
                    Button("Send to bench", role: .destructive) {
                        if let placement {
                            engine.assign(managerID: nil, venue: placement.venue, station: placement.station)
                            onToast("\(manager.name) is on the bench")
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
        let stations = Balance.venue(placement.venue).stations
        guard stations.indices.contains(placement.station) else { return "Assign" }
        return stations[placement.station].name
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
    @EnvironmentObject private var sound: SoundService

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    /// Stays up until dismissed - unlike a toast, a player who opens this tab a while after
    /// a drop still gets to see what they found.
    @ViewBuilder private var recipeDropBanner: some View {
        if !engine.unseenRecipeDrops.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                GlyphIcon("sparkles", tint: Theme.coin)
                    .frame(width: 20, height: 20)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("New find!")
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text(recipeDropSummary)
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { engine.clearUnseenRecipeDrops() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.ink.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .panel(Theme.panelRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.coin.opacity(0.5), lineWidth: 1.5)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var recipeDropSummary: String {
        let drops = engine.unseenRecipeDrops
        guard drops.count > 1 else {
            return drops.first.map(describe) ?? ""
        }
        return "\(drops.count) recipe drops while you were away - new cards joined your album, duplicates turned into gems."
    }

    private func describe(_ drop: Recipes.Drop) -> String {
        switch drop {
        case .none: return ""
        case .newCard(let venue, let station):
            return "You picked up the \(Balance.venue(venue).stations[station].name) recipe card."
        case .upgraded(let venue, let station, let stars):
            return "\(Balance.venue(venue).stations[station].name) recipe upgraded to \(stars)★."
        case .duplicateGems(let gems):
            return "A duplicate card converted into +\(gems) gems."
        }
    }

    var body: some View {
        IntroBanner(key: IntroKey.recipes, symbol: "star.square.fill",
                    title: "Cards drop as you level up",
                    detail: "Leveling a station has a chance to drop its recipe card. A duplicate upgrades that card's stars for more profit on that one station; a full set for a venue adds a bonus across the whole venue.")

        recipeDropBanner

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

                if engine.canCrownSignature(venue: venue.id) {
                    signaturePicker(venue: venue)
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

        // Paced: the tool chase opens with the first franchise (or first lucky drop).
        if engine.toolsRelevant {
            IntroBanner(key: IntroKey.tools, symbol: "wrench.and.screwdriver.fill",
                        title: "Kitchen Tools",
                        detail: "Rare equipment drops from the game's big moments - Rush Hours, VIP catches, Face-Off wins, catering deliveries. Once found, a tool works forever. Somewhere out there is a Gold Spatula.")
            toolShelf
        }
    }

    /// The tool collection: owned tools glow with their effects, unfound ones are dark
    /// silhouettes with a hint. The Gold Spatula row is deliberately visible from day one -
    /// a chase you can see is a chase you feel.
    private var toolShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("KITCHEN TOOLS")
                    .font(Theme.body(10, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(engine.state.tools.count) / \(Tools.all.count)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.textDim)
            }
            ForEach(Tools.all) { base in
                let owned = engine.state.tools.contains(base.id)
                // A tool that rolled above its base tier displays and pays out at that
                // higher rarity - see `Tools.rollRarity` and `ToolItem.scaled(to:)`.
                let tool = engine.state.toolRarities[base.id].map { base.scaled(to: $0) } ?? base
                HStack(spacing: 10) {
                    GlyphIcon(tool.symbol, tint: owned ? rarityColor(tool.rarity) : Theme.locked)
                        .frame(width: 18, height: 18)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.ink.opacity(0.5)))
                        .saturation(owned ? 1 : 0)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(owned ? tool.name : "???")
                            .font(Theme.body(12, weight: .black))
                            .foregroundStyle(owned ? Theme.text : Theme.textDim)
                        Text(owned ? tool.detail : hint(for: tool))
                            .font(Theme.body(10, weight: .medium))
                            .foregroundStyle(owned ? Theme.positive : Theme.textDim)
                    }
                    Spacer(minLength: 0)
                    Text(tool.rarity.label)
                        .font(Theme.body(8, weight: .black))
                        .foregroundStyle(owned ? Theme.ink : Theme.textDim)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(owned ? rarityColor(tool.rarity) : Theme.ink.opacity(0.4)))
                }
            }
        }
        .padding(12)
        .panel(Theme.panel)
    }

    private func rarityColor(_ rarity: ToolItem.Rarity) -> Color {
        switch rarity {
        case .common: return Theme.positive
        case .rare: return Theme.gem
        case .epic: return Color(hex: "#B07BE8")
        case .legendary: return Theme.coin
        }
    }

    private func hint(for tool: ToolItem) -> String {
        tool.rarity == .legendary
            ? "The rarest thing in the game. Keep playing the big moments."
            : "Drops from Rush Hours, VIPs, Face-Offs, and catering."
    }

    /// The fusion endgame: a fully 3-starred set lets the player crown one station as the
    /// venue's Signature Dish. Same first-open explainer treatment as every other system.
    @ViewBuilder
    private func signaturePicker(venue: VenueSpec) -> some View {
        IntroBanner(key: IntroKey.signature, symbol: "crown.fill",
                    title: "Signature Dish unlocked",
                    detail: "This venue's whole set is 3-starred - crown one station its Signature Dish for ×1.5 profit there. You can re-crown a different station anytime, free.")

        VStack(alignment: .leading, spacing: 6) {
            Text("SIGNATURE DISH · ×1.5")
                .font(Theme.body(9, weight: .black))
                .tracking(0.6)
                .foregroundStyle(Theme.coin)
            HStack(spacing: 6) {
                ForEach(venue.stations) { spec in
                    let crowned = engine.state.signatureDish[venue.id] == spec.id
                    Button {
                        if engine.crownSignatureDish(venue: venue.id, station: spec.id) {
                            Haptics.success()
                            sound.play(.reward)
                        }
                    } label: {
                        FoodSprite(art: spec.art, colors: spec.colors)
                            .equatable()
                            .frame(width: 30, height: 30)
                            .padding(5)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(crowned ? Theme.coin.opacity(0.35) : Theme.ink.opacity(0.4)))
                            .overlay(alignment: .topTrailing) {
                                if crowned {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(Theme.coin)
                                        .offset(x: 3, y: -4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Crown \(spec.name) as Signature Dish")
                }
            }
        }
    }

    private func card(venue: VenueSpec, spec: StationSpec) -> some View {
        let stars = Recipes.stars(engine.state.recipeCards, venue: venue.id, station: spec.id)
        let owned = stars > 0

        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(owned ? Theme.ink.opacity(0.55) : Theme.ink.opacity(0.3))
                FoodSprite(art: spec.art, colors: spec.colors)
                    .equatable()
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

// MARK: - Errands

private struct ErrandsSection: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void

    var body: some View {
        IntroBanner(key: IntroKey.errands, symbol: "hourglass",
                    title: "A quick lump sum, at a cost",
                    detail: "Sending a manager on an errand pays out gems and coins when it finishes, but pulls them off their station for the whole duration - best for someone already on the bench, not one currently automating something.")

        if engine.claimableErrands.count > 1 {
            IntroBanner(key: IntroKey.claimAllErrandsIntro, symbol: "checkmark.circle.fill",
                        title: "Claim everything at once",
                        detail: "When more than one errand is ready, this collects them all in a single tap instead of one at a time.")
            claimAllButton
        }

        ForEach(0..<Errands.maxSlots, id: \.self) { slot in
            slotView(slot)
        }

        // Paced: Face-Offs surface once a crew is fieldable (or the player's a veteran).
        if engine.faceOffsRelevant {
            IntroBanner(key: IntroKey.expeditions, symbol: "trophy.fill",
                        title: "Food Court Face-Offs",
                        detail: "Send your three best benched managers to out-cook a rival crew. Higher stakes pay better - and the Grand Face-Off can bring home a new Epic recruit. Rarity and long service (bond) decide your odds, shown before you commit.")
            faceOffCard
        }

        Text("Send an idle manager on an errand for a lump sum of gems and coins when they return - a tradeoff against staffing a station, not a free bonus.")
            .font(Theme.body(11, weight: .medium))
            .foregroundStyle(Theme.textDim)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    private var claimAllButton: some View {
        Button {
            let claimed = engine.claimAllErrands()
            guard claimed > 0 else { return }
            Haptics.success()
            sound.play(.bigReward)
            onToast("Claimed \(Format.plural(claimed, "errand"))")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Claim All (\(engine.claimableErrands.count))")
            }
            .font(Theme.body(13, weight: .black))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.positive, shadow: Theme.positive.opacity(0.5), radius: 12))
    }

    private var activeErrands: [ActiveErrand] { engine.state.errands }

    /// The best three on the bench, by fight value - the launcher sends these, shown by
    /// name so the pick is transparent even though it's automatic.
    private var bestCrew: [OwnedManager] {
        engine.state.unassignedManagers
            .sorted { Expeditions.crewScore([$0]) > Expeditions.crewScore([$1]) }
            .prefix(Expeditions.crewSize).map { $0 }
    }

    @ViewBuilder private var faceOffCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FACE-OFF")
                .font(Theme.body(10, weight: .black))
                .tracking(0.6)
                .foregroundStyle(Theme.textDim)

            if let expedition = engine.state.expedition {
                let tier = Expeditions.tier(expedition.tier)
                HStack(spacing: 8) {
                    GlyphIcon("trophy.fill", tint: Theme.coin)
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tier.title)
                            .font(Theme.body(13, weight: .black))
                            .foregroundStyle(Theme.text)
                        Text(crewNames(expedition.managerIDs))
                            .font(Theme.body(10, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer(minLength: 0)
                    if expedition.isComplete(at: engine.state.now) {
                        Button {
                            if let result = engine.resolveExpedition() {
                                Haptics.success()
                                sound.play(result.won ? .bigReward : .denied)
                            }
                        } label: {
                            Text("Results")
                                .font(Theme.body(12, weight: .black))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                        .buttonStyle(ChunkyButtonStyle(fill: Theme.positive,
                                                       shadow: Theme.positive.opacity(0.5), radius: 10))
                    } else {
                        Text(Format.duration(expedition.remaining(at: engine.state.now)))
                            .font(Theme.numeric(13))
                            .foregroundStyle(Theme.textDim)
                    }
                }
            } else if bestCrew.count < Expeditions.crewSize {
                Text("Needs \(Expeditions.crewSize) benched managers - hire or unassign to field a crew.")
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            } else {
                let crew = bestCrew
                Text("Crew: \(crewNames(crew.map(\.id)))")
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.text)
                ForEach(Expeditions.tiers) { tier in
                    let chance = Expeditions.winChance(score: Expeditions.crewScore(crew), tier: tier)
                    Button {
                        if engine.startExpedition(managerIDs: crew.map(\.id), tierID: tier.id) {
                            Haptics.thud()
                            sound.play(.purchase)
                            onToast("\(tier.title) underway - back in \(Format.trim(tier.hours))h")
                        }
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tier.title)
                                    .font(Theme.body(12, weight: .black))
                                    .foregroundStyle(Theme.text)
                                Text(tier.detail)
                                    .font(Theme.body(10, weight: .medium))
                                    .foregroundStyle(Theme.textDim)
                            }
                            Spacer(minLength: 0)
                            Text("\(Int((chance * 100).rounded()))% win")
                                .font(Theme.numeric(12))
                                .foregroundStyle(chance >= 0.75 ? Theme.positive
                                                 : (chance >= 0.4 ? Theme.coin : Theme.negative))
                        }
                        .padding(10)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink, radius: 12))
                }
            }
        }
        .padding(12)
        .panel(Theme.panel)
    }

    private func crewNames(_ ids: [String]) -> String {
        ids.compactMap { engine.state.manager(id: $0)?.name }.joined(separator: " · ")
    }

    private func slotView(_ slot: Int) -> some View {
        Group {
            if slot < activeErrands.count {
                errandRow(activeErrands[slot])
            } else {
                emptySlotRow
            }
        }
    }

    private func errandRow(_ errand: ActiveErrand) -> some View {
        let manager = engine.state.manager(id: errand.managerID)
        let done = errand.isComplete(at: engine.state.now)
        let remaining = errand.remaining(at: engine.state.now)

        return HStack(spacing: 12) {
            ZStack {
                if let spec = manager?.spec {
                    ManagerRarityFrame(rarity: spec.rarity)
                    CustomerSprite(seed: spec.portraitSeed)
                        .equatable()
                        .frame(width: 26, height: 36)
                        .offset(y: 3)
                } else {
                    Circle().fill(Theme.ink.opacity(0.5))
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(manager?.name ?? "Manager")
                    .font(Theme.body(13, weight: .black))
                    .foregroundStyle(Theme.text)
                Text(done ? "Errand complete" : "Back in \(Format.duration(remaining))")
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(done ? Theme.positive : Theme.textDim)
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        GemIcon().frame(width: 11, height: 11)
                        Text("\(errand.rewardGems)")
                    }
                    HStack(spacing: 3) {
                        CoinIcon().frame(width: 11, height: 11)
                        // Live value - coins are priced at collection, not at start.
                        Text("≈\(Format.currency(engine.errandCoinValue(errand)))")
                    }
                }
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)

            if done {
                Button("Collect") {
                    if let claimed = engine.collectErrand(id: errand.id) {
                        Haptics.success()
                        sound.play(.reward)
                        onToast("+\(claimed.rewardGems) gems · \(Format.currency(claimed.rewardCoins)) coins")
                    }
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.positive,
                                               shadow: Theme.positive.opacity(0.5), radius: 10))
            }
        }
        .padding(12)
        .panel(done ? Theme.panelRaised : Theme.panel)
    }

    @State private var showPicker = false

    private var emptySlotRow: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Empty slot")
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text("Send a manager on an errand")
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .panel(Theme.panel)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            ErrandManagerPicker(onToast: onToast)
        }
    }
}

/// Two-step errand picker (manager, then duration) replacing a nested `Menu` that rendered
/// as a stack of misaligned iOS submenus - especially confusing once two managers on the
/// bench shared a name, since a plain text row was the only way to tell them apart.
private struct ErrandManagerPicker: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedManager: OwnedManager?

    var body: some View {
        SheetScaffold(title: selectedManager == nil ? "Send on Errand" : "Choose Duration",
                      subtitle: selectedManager?.name) {
            if let manager = selectedManager {
                hoursList(for: manager)
            } else {
                managerList
            }
        }
    }

    @ViewBuilder private var managerList: some View {
        if engine.state.unassignedManagers.isEmpty {
            Text("No idle managers on the bench")
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .padding(.top, 20)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(engine.state.unassignedManagers) { manager in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { selectedManager = manager }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    ManagerRarityFrame(rarity: manager.spec.rarity)
                                    CustomerSprite(seed: manager.spec.portraitSeed)
                                        .equatable()
                                        .frame(width: 26, height: 36)
                                        .offset(y: 3)
                                }
                                .frame(width: 46, height: 46)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(manager.name)
                                        .font(Theme.body(13, weight: .black))
                                        .foregroundStyle(Theme.text)
                                    Text(manager.spec.rarity.label)
                                        .font(Theme.body(9, weight: .black))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(rarityColor(manager.spec.rarity)))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.textDim)
                            }
                            .padding(12)
                            .panel(Theme.panel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func hoursList(for manager: OwnedManager) -> some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { selectedManager = nil }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(Theme.body(12, weight: .bold))
                .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Errands.options) { option in
                Button {
                    if engine.startErrand(managerID: manager.id, hours: option.hours) {
                        Haptics.success()
                        sound.play(.reward)
                        onToast("\(manager.name) is out on an errand")
                        dismiss()
                    }
                } label: {
                    Text(option.label)
                        .font(Theme.body(14, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink, radius: 12))
            }
            Spacer(minLength: 0)
        }
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
