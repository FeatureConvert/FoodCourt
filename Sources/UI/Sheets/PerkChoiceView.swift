import SwiftUI

/// Shown when a station crosses a choice milestone. Three options, one pick, permanent.
struct PerkChoiceView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    @Environment(\.dismiss) private var dismiss

    let station: Int
    let onToast: (String) -> Void

    private var venueID: Int { engine.state.currentVenue }
    private var spec: StationSpec { Balance.venue(venueID).stations[station] }
    private var level: Int? { engine.pendingPerkLevel(venue: venueID, station: station) }

    @State private var celebratingIndex: Int?
    /// Two-tap confirmation: with only four choices per run, a mis-tap burning one would
    /// hurt - same tap-again pattern the Franchise and Legacy buttons already use.
    @State private var armedIndex: Int?

    var body: some View {
        SheetScaffold(title: "Level \(level.map(String.init) ?? "") Perk",
                      subtitle: "\(spec.name) — \(engine.perkChoicesRemaining) of \(Balance.perkChoicesPerRun) choices left this run") {
            IntroBanner(key: IntroKey.perks, symbol: "questionmark.circle.fill",
                        title: "What's a perk?",
                        detail: "A station-specific upgrade that lasts until your next Franchise. You get \(Balance.perkChoicesPerRun) choices per run, so pick which stations deserve a personal build - milestone bonuses still land automatically everywhere else.")

            HStack(spacing: 10) {
                FoodSprite(art: spec.art, colors: spec.colors)
                    .equatable()
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
                    let armed = armedIndex == perk.id
                    Button {
                        if armed {
                            engine.choosePerk(venue: venueID, station: station, level: level, index: perk.id)
                            Haptics.success()
                            sound.play(.reward)
                            onToast("\(spec.name): \(perk.title)")
                            celebratingIndex = perk.id
                            // A beat to let the confetti actually play before the sheet
                            // closes, matching DailyRewardView's claim-then-dismiss timing.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { dismiss() }
                        } else {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                armedIndex = perk.id
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            GlyphIcon(perk.symbol, tint: armed ? Theme.ink : Theme.star)
                                .frame(width: 22, height: 22)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(armed ? Theme.star : Theme.ink.opacity(0.5)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(perk.title)
                                    .font(Theme.body(14, weight: .black))
                                    .foregroundStyle(Theme.text)
                                Text(armed ? "Tap again to lock it in - this spends 1 of \(engine.perkChoicesRemaining) choices" : perk.detail)
                                    .font(Theme.body(11, weight: .bold))
                                    .foregroundStyle(armed ? Theme.coin : Theme.positive)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: armed ? "checkmark.circle.fill" : "chevron.right")
                                .font(.system(size: armed ? 16 : 12, weight: .black))
                                .foregroundStyle(armed ? Theme.positive : Theme.textDim)
                        }
                        .padding(12)
                    }
                    .buttonStyle(ChunkyButtonStyle(fill: armed ? Theme.panelRaised.opacity(0.9) : Theme.panelRaised,
                                                   shadow: armed ? Theme.star.opacity(0.6) : Theme.ink))
                    .overlay {
                        if celebratingIndex == perk.id { ConfettiBurstView() }
                    }
                }
            }

            // Choices are precious now - walking away and deciding later is always allowed.
            Button {
                dismiss()
            } label: {
                Text("Decide later")
                    .font(Theme.body(13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.panel, shadow: Theme.ink, radius: 12))

            Text("Perks stack with the milestone bonus you just earned. This station keeps the offer - come back anytime from its row.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}
