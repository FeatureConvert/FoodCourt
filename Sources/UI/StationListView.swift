import SwiftUI

struct StationListView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void
    let onChoosePerk: (Int) -> Void

    private var venue: VenueSpec { Balance.venue(engine.state.currentVenue) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("STATIONS")
                    .font(Theme.body(12, weight: .black))
                    .foregroundStyle(Theme.textDim)
                if engine.costInflation > 1.01 {
                    // A board that's gone a long time without a franchise reset gets
                    // proportionally pricier - this is the one place that's visible during
                    // normal play rather than only inside the Franchise sheet.
                    Text("\(Format.bonus(multiplier: engine.costInflation)) COSTS")
                        .font(Theme.body(9, weight: .black))
                        .foregroundStyle(Theme.negative)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.negative.opacity(0.16)))
                }
                Spacer()
                BuyQuantityPicker()
            }
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(venue.stations) { spec in
                        StationCardView(spec: spec, onToast: onToast, onChoosePerk: onChoosePerk)
                    }
                    if let next = engine.nextLockedVenue {
                        NextVenueTeaser(venue: next, onToast: onToast)
                    }
                    Color.clear.frame(height: 6)
                }
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct BuyQuantityPicker: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BuyQuantity.allCases) { quantity in
                let selected = engine.buyQuantity == quantity
                Button {
                    Haptics.tap()
                    sound.play(.tap)
                    engine.buyQuantity = quantity
                } label: {
                    Text(quantity.label)
                        .font(Theme.body(11, weight: .black))
                        .foregroundStyle(selected ? Theme.ink : Theme.textDim)
                        .frame(width: 42, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Theme.coin : Theme.panelRaised)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The card that does most of the work: cook, level up, staff, and spend perk choices.
struct StationCardView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let spec: StationSpec
    let onToast: (String) -> Void
    let onChoosePerk: (Int) -> Void

    private var venueID: Int { engine.state.currentVenue }
    private var state: StationState { engine.state.venues[venueID].stations[spec.id] }
    private var palette: VenuePalette { VenuePalette.of(Balance.venue(venueID).theme) }
    private var cycle: TimeInterval { engine.state.cycleTime(venue: venueID, station: spec.id) }
    private var payout: Double {
        engine.state.baseRevenue(venue: venueID, station: spec.id) * engine.payoutMultiplier
    }
    private var recipeStars: Int {
        Recipes.stars(engine.state.recipeCards, venue: venueID, station: spec.id)
    }
    private var pendingPerk: Int? {
        engine.pendingPerkLevel(venue: venueID, station: spec.id)
    }

    /// Whether the live customer-order system (distinct from the tutorial's own highlight) is
    /// currently asking for a serve on this exact station.
    private var isOrderTarget: Bool {
        guard let order = engine.activeOrder else { return false }
        return order.venue == venueID && order.station == spec.id
    }

    var body: some View {
        HStack(spacing: 12) {
            cooker
            details
            Spacer(minLength: 0)
            actions
        }
        .padding(12)
        .panel(state.isOwned ? Theme.panel : Theme.panel.opacity(0.6))
        .overlay(alignment: .top) {
            ServeBurstOverlay(event: engine.lastServe[spec.id])
                .offset(y: 10)
        }
        .overlay {
            if isOrderTarget {
                // Same pulsing-ring technique as TutorialHighlight, kept separate since that
                // modifier is keyed specifically to TutorialTarget rather than a plain flag.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = 0.5 + 0.5 * sin(t * 4)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.coin, lineWidth: 2 + 1.5 * pulse)
                        .opacity(0.55 + 0.45 * pulse)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if isOrderTarget {
                Text("ORDER UP")
                    .font(Theme.body(9, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.coin))
                    .offset(x: 8, y: -8)
            }
        }
    }

    // MARK: Cooker

    private var cooker: some View {
        Button {
            if state.isOwned {
                engine.tap(station: spec.id)
                Haptics.tap()
                sound.play(.tap)
            } else {
                purchase()
            }
        } label: {
            ZStack {
                Circle().fill(Theme.ink.opacity(0.55))
                CookerRing(elapsed: state.elapsed, isRunning: state.isRunning, cycle: cycle,
                           accent: palette.accent, lastAdvanceAt: engine.lastAdvanceAt)

                FoodSprite(art: spec.art, colors: spec.colors)
                    .equatable()
                    .frame(width: 44, height: 44)
                    .saturation(state.isOwned ? 1 : 0)
                    .opacity(state.isOwned ? 1 : 0.45)

                if !state.isOwned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Theme.text)
                        .shadow(radius: 3)
                }
            }
            .frame(width: 66, height: 66)
        }
        .buttonStyle(.plain)
        .tutorialHighlight(spec.id == 0 ? .stationCooker : nil)
        .scaleEffect(state.isRunning ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: state.isRunning)
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(spec.name)
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if recipeStars > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<recipeStars, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Theme.star)
                        }
                    }
                }
            }

            if state.isOwned {
                HStack(spacing: 6) {
                    Text("Lv \(Format.count(state.level))")
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                    Text("+\(Format.currency(payout))")
                        .font(Theme.body(11, weight: .black))
                        .foregroundStyle(Theme.coin)
                    Text(Format.cycle(cycle))
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                milestoneBar
                staffLine
            } else {
                Text("Tap to open this station")
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    @ViewBuilder
    private var staffLine: some View {
        if let manager = engine.state.stationManager(venue: venueID, station: spec.id) {
            HStack(spacing: 4) {
                CustomerSprite(seed: manager.spec.portraitSeed)
                    .equatable()
                    .frame(width: 12, height: 17)
                Text(manager.name)
                    .font(Theme.body(9, weight: .bold))
                    .foregroundStyle(Theme.positive)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var milestoneBar: some View {
        if let next = Balance.nextMilestone(level: state.level) {
            let previous = Balance.milestones.last { $0.level <= state.level }?.level ?? 0
            let span = max(1, next.level - previous)
            let done = max(0, state.level - previous)
            VStack(alignment: .leading, spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.ink.opacity(0.6))
                        Capsule().fill(palette.accent)
                            .frame(width: geo.size.width * min(1, Double(done) / Double(span)))
                    }
                }
                .frame(height: 5)
                Text("Lv \(next.level): \(next.label)")
                    .font(Theme.body(9, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .frame(maxWidth: 130)
        } else {
            Text("Fully upgraded")
                .font(Theme.body(9, weight: .bold))
                .foregroundStyle(Theme.positive)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 6) {
            Button(action: purchase) {
                VStack(spacing: 1) {
                    Text(state.isOwned ? buyLabel : "UNLOCK")
                        .font(Theme.body(10, weight: .black))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(Format.price(engine.price(for: spec.id)))
                        .font(Theme.numeric(13))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 92, height: 42)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: affordable ? Theme.positive : Theme.locked,
                shadow: affordable ? Theme.positive.opacity(0.55) : Theme.ink,
                disabled: !affordable,
                radius: 12
            ))
            .disabled(!affordable)
            .tutorialHighlight(spec.id == 0 ? .stationBuy : nil)

            secondaryButton
        }
    }

    private var affordable: Bool { engine.canAfford(index: spec.id) }

    private var buyLabel: String {
        engine.buyQuantity == .max
            ? "MAX · \(Format.count(engine.quantity(for: spec.id)))"
            : engine.buyQuantity.label
    }

    /// A perk waiting to be spent always outranks the hire button - it's free value the
    /// player has already earned.
    @ViewBuilder
    private var secondaryButton: some View {
        if !state.isOwned {
            Color.clear.frame(width: 92, height: 26)
        } else if pendingPerk != nil {
            Button { onChoosePerk(spec.id) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .black))
                    Text("PERK").font(Theme.body(10, weight: .black))
                }
                .frame(width: 92, height: 26)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.star, shadow: Theme.coinDeep, radius: 10))
        } else if state.isStaffed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                Text("STAFFED")
            }
            .font(Theme.body(10, weight: .black))
            .foregroundStyle(Theme.positive)
            .frame(width: 92, height: 26)
        } else if engine.state.tutorial.current == .hireManager, spec.id == 0 {
            Button(action: hire) {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill.badge.plus")
                        .font(.system(size: 10, weight: .black))
                    Text("FREE")
                        .font(Theme.body(10, weight: .black))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 92, height: 26)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.gemDeep, shadow: Theme.ink, radius: 10))
            .tutorialHighlight(.stationHire)
        } else {
            let cost = engine.managerCost(for: spec.id)
            let canHire = engine.state.coins >= cost
            Button(action: hire) {
                HStack(spacing: 4) {
                    Image(systemName: canHire ? "person.fill.badge.plus" : "diamond.fill")
                        .font(.system(size: 10, weight: .black))
                    Text(canHire ? Format.price(cost) : "\(GemSpend.instantManagerGemCost)")
                        .font(Theme.body(10, weight: .black))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 92, height: 26)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: canHire ? Theme.gemDeep : Theme.panelRaised,
                shadow: Theme.ink, radius: 10
            ))
            .tutorialHighlight(spec.id == 0 ? .stationHire : nil)
        }
    }

    // MARK: Intents

    private func purchase() {
        if engine.buy(station: spec.id) {
            Haptics.thud()
            sound.play(.purchase)
        } else {
            sound.play(.denied)
            onToast("Not enough coins")
        }
    }

    private func hire() {
        // The tutorial's guided first hire has to always be reachable - a new player only
        // starts with 25 gems, well under the 100-gem instant-hire price, and may not have
        // saved up the coin cost yet either after the previous step spent coins on a level.
        // Route it through the same free-grant path debug tooling uses rather than ever
        // charging for it.
        if engine.state.tutorial.current == .hireManager, spec.id == 0 {
            if engine.hireManager(for: spec.id, free: true) {
                Haptics.success()
                sound.play(.reward)
                onToast("\(spec.name) is now staffed")
            }
            return
        }

        let cost = engine.managerCost(for: spec.id)
        if engine.state.coins >= cost {
            if engine.hireManager(for: spec.id) {
                Haptics.success()
                sound.play(.reward)
                onToast("\(spec.name) is now staffed")
            }
        } else {
            switch GemSpend.hireManagerWithGems(station: spec.id, engine: engine) {
            case .success:
                Haptics.success()
                sound.play(.reward)
                onToast("\(spec.name) is now staffed")
            case .insufficientGems:
                sound.play(.denied)
                onToast("Need \(GemSpend.instantManagerGemCost) gems or \(Format.price(cost))")
            case .nothingToDo(let message):
                onToast(message)
            }
        }
    }
}

/// The station's progress ring.
///
/// Past a certain speed a per-cycle sweep stops reading as progress and starts reading as a
/// flicker - a maxed station completes ten-plus cycles a second, and the ring just strobes.
/// Below the threshold the ring locks to full and switches to a glow with a slow sweep, which
/// says "running flat out" instead, and doubles as a reward for having got it that fast.
private struct CookerRing: View {
    /// Elapsed as of the last engine tick; the view interpolates forward from there.
    let elapsed: TimeInterval
    let isRunning: Bool
    let cycle: TimeInterval
    let accent: Color
    let lastAdvanceAt: Date

    /// A sweep is still legible at roughly three cycles a second; past that it is a blur.
    static let flatOutBelow: TimeInterval = 0.35

    private var isFlatOut: Bool { cycle < Self.flatOutBelow }

    /// One timeline for both modes, running at the display's refresh rate. Sampling the
    /// engine's `elapsed` directly gave a 0.6s cycle only twelve frames, which is what made
    /// the ring look like it was running at a low frame rate.
    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                Circle().stroke(Theme.stroke, lineWidth: 5)

                if isFlatOut {
                    flatOut(at: timeline.date)
                } else {
                    Circle()
                        .trim(from: 0, to: interpolatedProgress(at: timeline.date))
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }

    /// Carries the last sampled elapsed forward by however long it has been since that tick.
    private func interpolatedProgress(at date: Date) -> Double {
        guard isRunning, cycle > 0 else { return 0 }
        let sinceTick = max(0, date.timeIntervalSince(lastAdvanceAt))
        return min(1, (elapsed + sinceTick) / cycle)
    }

    private func flatOut(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let pulse = 0.5 + 0.5 * sin(t * 4.5)
        let sweep = Angle.degrees((t * 400).truncatingRemainder(dividingBy: 360))

        return ZStack {
            Circle()
                .stroke(accent, lineWidth: 5)
                .shadow(color: accent.opacity(0.35 + 0.45 * pulse), radius: 4 + 5 * pulse)
            Circle()
                .trim(from: 0, to: 0.2)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [accent.opacity(0), .white.opacity(0.85)]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(sweep)
        }
    }
}

/// Sits at the bottom of the station list so the next venue is always visible as a goal.
struct NextVenueTeaser: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let venue: VenueSpec
    let onToast: (String) -> Void

    var body: some View {
        let palette = VenuePalette.of(venue.theme)
        let affordable = engine.canUnlock(venue)

        Button {
            if engine.unlock(venue) {
                Haptics.success()
                sound.play(.reward)
                onToast("\(venue.name) is open for business!")
            } else {
                sound.play(.denied)
                onToast("Need \(Format.price(engine.unlockCost(for: venue))) to open \(venue.name)")
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(palette.counter)
                    FoodSprite(art: venue.stations[1].art, colors: venue.stations[1].colors)
                        .equatable()
                        .frame(width: 40, height: 40)
                        .saturation(affordable ? 1 : 0.2)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 2) {
                    Text("OPEN \(venue.name.uppercased())")
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text("Earns ×\(Format.currency(venue.revenueMultiplier)) more per dish")
                        .font(Theme.body(10, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
                Text(Format.price(engine.unlockCost(for: venue)))
                    .font(Theme.numeric(14))
                    .foregroundStyle(affordable ? Theme.coin : Theme.textDim)
            }
            .padding(12)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: affordable ? palette.counter : Theme.panel,
            shadow: affordable ? palette.counterEdge : Theme.ink
        ))
    }
}
