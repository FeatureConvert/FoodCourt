import SwiftUI

/// Shown when a station crosses a choice milestone. Three options, one pick, permanent.
struct PerkChoiceView: View {
    @EnvironmentObject private var engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    let station: Int
    let onToast: (String) -> Void

    private var venueID: Int { engine.state.currentVenue }
    private var spec: StationSpec { Balance.venue(venueID).stations[station] }
    private var level: Int? { engine.pendingPerkLevel(venue: venueID, station: station) }

    var body: some View {
        SheetScaffold(title: "Level \(level.map(String.init) ?? "") Perk",
                      subtitle: "\(spec.name) — pick one, it's permanent") {
            HStack(spacing: 10) {
                FoodSprite(art: spec.art, colors: spec.colors)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.name)
                        .font(Theme.body(15, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text("Lv \(Format.count(engine.state.venues[venueID].stations[station].level))")
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            .padding(12)
            .panel(Theme.panel)

            if let level {
                ForEach(Perks.choices(at: level)) { perk in
                    Button {
                        engine.choosePerk(venue: venueID, station: station, level: level, index: perk.id)
                        Haptics.success()
                        onToast("\(spec.name): \(perk.title)")
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: perk.symbol)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.star)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Theme.ink.opacity(0.5)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(perk.title)
                                    .font(Theme.body(14, weight: .black))
                                    .foregroundStyle(Theme.text)
                                Text(perk.detail)
                                    .font(Theme.body(11, weight: .bold))
                                    .foregroundStyle(Theme.positive)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(Theme.textDim)
                        }
                        .padding(12)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
                }
            }

            Text("Perks stack with the milestone bonus you just earned.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled(true)
    }
}
