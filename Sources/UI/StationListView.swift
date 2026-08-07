import SwiftUI

struct StationListView: View {
    @EnvironmentObject private var engine: GameEngine
    let onToast: (String) -> Void

    private var venue: VenueSpec { Balance.venue(engine.state.currentVenue) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("STATIONS")
                    .font(Theme.body(12, weight: .black))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                BuyQuantityPicker()
            }
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(venue.stations) { spec in
                        StationCardView(spec: spec, onToast: onToast)
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

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BuyQuantity.allCases) { quantity in
                let selected = engine.buyQuantity == quantity
                Button {
                    Haptics.tap()
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

/// The card that does most of the work: cook, level up, and staff a single station.
struct StationCardView: View {
    @EnvironmentObject private var engine: GameEngine
    let spec: StationSpec
    let onToast: (String) -> Void

    private var state: StationState {
        engine.state.venues[engine.state.currentVenue].stations[spec.id]
    }
    private var palette: VenuePalette {
        VenuePalette.of(Balance.venue(engine.state.currentVenue).theme)
    }
    private var cycle: TimeInterval { Balance.cycleTime(spec: spec, level: state.level) }
    private var progress: Double {
        state.isRunning ? min(1, state.elapsed / cycle) : 0
    }
    private var payout: Double {
        Balance.revenuePerCycle(spec: spec, level: state.level) * engine.state.globalMultiplier
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
    }

    // MARK: Cooker

    private var cooker: some View {
        Button {
            if state.isOwned {
                if engine.tap(station: spec.id) { Haptics.tap() }
            } else {
                purchase()
            }
        } label: {
            ZStack {
                Circle().fill(Theme.ink.opacity(0.55))
                Circle()
                    .stroke(Theme.stroke, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                FoodSprite(art: spec.art, colors: spec.colors)
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
        .scaleEffect(state.isRunning ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: state.isRunning)
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(spec.name)
                .font(Theme.body(14, weight: .black))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

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
            } else {
                Text("Tap to open this station")
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .frame(minWidth: 96, alignment: .leading)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(Format.currency(engine.price(for: spec.id)))
                        .font(Theme.numeric(13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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

            managerButton
        }
    }

    private var affordable: Bool { engine.canAfford(index: spec.id) }

    /// Fixed quantities already say how many; only MAX needs the resolved count spelled out.
    private var buyLabel: String {
        engine.buyQuantity == .max
            ? "MAX · \(Format.count(engine.quantity(for: spec.id)))"
            : engine.buyQuantity.label
    }

    @ViewBuilder
    private var managerButton: some View {
        if state.isOwned {
            if state.hasManager {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("STAFFED")
                }
                .font(Theme.body(10, weight: .black))
                .foregroundStyle(Theme.positive)
                .frame(width: 92, height: 26)
            } else {
                let cost = engine.managerCost(for: spec.id)
                let canHire = engine.state.coins >= cost
                Button(action: hire) {
                    HStack(spacing: 4) {
                        Image(systemName: canHire ? "person.fill.badge.plus" : "diamond.fill")
                            .font(.system(size: 10, weight: .black))
                        Text(canHire ? Format.currency(cost) : "\(GemSpend.instantManagerGemCost)")
                            .font(Theme.body(10, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 92, height: 26)
                }
                .buttonStyle(ChunkyButtonStyle(
                    fill: canHire ? Theme.gemDeep : Theme.panelRaised,
                    shadow: Theme.ink,
                    radius: 10
                ))
            }
        } else {
            Color.clear.frame(width: 92, height: 26)
        }
    }

    // MARK: Intents

    private func purchase() {
        if engine.buy(station: spec.id) {
            Haptics.thud()
        } else {
            onToast("Not enough coins")
        }
    }

    /// Coins first; if the player is short, the same button spends gems instead. Two taps
    /// for the same intent would be worse than one that always works.
    private func hire() {
        let cost = engine.managerCost(for: spec.id)
        if engine.state.coins >= cost {
            if engine.hireManager(for: spec.id) {
                Haptics.success()
                onToast("\(spec.name) is now staffed")
            }
        } else {
            switch GemSpend.hireManagerWithGems(station: spec.id, engine: engine) {
            case .success:
                Haptics.success()
                onToast("\(spec.name) is now staffed")
            case .insufficientGems:
                onToast("Need \(GemSpend.instantManagerGemCost) gems or \(Format.currency(cost))")
            case .nothingToDo(let message):
                onToast(message)
            }
        }
    }
}

/// Sits at the bottom of the station list so the next venue is always visible as a goal.
struct NextVenueTeaser: View {
    @EnvironmentObject private var engine: GameEngine
    let venue: VenueSpec
    let onToast: (String) -> Void

    var body: some View {
        let palette = VenuePalette.of(venue.theme)
        let affordable = engine.canUnlock(venue)

        Button {
            if engine.unlock(venue) {
                Haptics.success()
                onToast("\(venue.name) is open for business!")
            } else {
                onToast("Need \(Format.currency(venue.unlockCost)) to open \(venue.name)")
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(palette.counter)
                    FoodSprite(art: venue.stations[1].art, colors: venue.stations[1].colors)
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
                Text(Format.currency(venue.unlockCost))
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
