import SwiftUI

/// Purely visual, coin-priced skins for one venue's room. Never touches profit - see
/// `GameEngine.skinPrice`.
struct CosmeticsView: View {
    @EnvironmentObject private var engine: GameEngine
    let venue: Int
    let onToast: (String) -> Void

    private var spec: VenueSpec { Balance.venue(venue) }

    var body: some View {
        SheetScaffold(title: "\(spec.name) Look", subtitle: "Purely cosmetic - never touches profit") {
            ForEach(VenuePalette.skinIDs, id: \.self) { skin in
                row(skin)
            }
        }
    }

    private func row(_ skin: String) -> some View {
        let palette = VenuePalette.of(spec.theme, skin: skin)
        let equipped = engine.state.skin(venue: venue) == skin
        let unlocked = engine.state.hasUnlockedSkin(venue: venue, skin: skin)
        let price = engine.skinPrice(venue: venue)

        return HStack(spacing: 12) {
            HStack(spacing: -8) {
                Circle().fill(palette.wallTop).frame(width: 28, height: 28)
                Circle().fill(palette.counter).frame(width: 28, height: 28)
                Circle().fill(palette.accent).frame(width: 28, height: 28)
            }
            .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            .padding(.trailing, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(skin.capitalized)
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(Theme.text)
                Text(equipped ? "Equipped" : (unlocked ? "Owned" : "\(Format.price(price)) coins"))
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(equipped ? Theme.positive : Theme.textDim)
            }
            Spacer(minLength: 0)

            Button(equipped ? "Equipped" : (unlocked ? "Equip" : "Unlock")) {
                if unlocked {
                    if engine.setSkin(venue: venue, skin: skin) {
                        Haptics.success()
                        onToast("\(skin.capitalized) equipped")
                    }
                } else if engine.unlockSkin(venue: venue, skin: skin) {
                    Haptics.success()
                    onToast("\(skin.capitalized) unlocked")
                } else {
                    onToast("Not enough coins")
                }
            }
            .buttonStyle(ChunkyButtonStyle(fill: equipped ? Theme.locked : Theme.positive,
                                           shadow: equipped ? Theme.ink : Theme.positive.opacity(0.5),
                                           disabled: equipped))
            .disabled(equipped)
        }
        .padding(12)
        .panel(equipped ? Theme.panelRaised : Theme.panel)
    }
}
