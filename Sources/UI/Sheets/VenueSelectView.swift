import SwiftUI

struct VenueSelectView: View {
    @EnvironmentObject private var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    let onToast: (String) -> Void

    var body: some View {
        SheetScaffold(title: "Your Food Court", subtitle: "Every open venue keeps earning, even while you're elsewhere") {
            ForEach(Balance.venues) { venue in
                row(venue)
            }
        }
    }

    private func row(_ venue: VenueSpec) -> some View {
        let palette = VenuePalette.of(venue.theme)
        let unlocked = engine.state.venues[venue.id].unlocked
        let current = engine.state.currentVenue == venue.id
        let affordable = engine.canUnlock(venue)

        return Button {
            if unlocked {
                engine.switchTo(venue: venue.id)
                Haptics.tap()
                dismiss()
            } else if engine.unlock(venue) {
                Haptics.success()
                onToast("\(venue.name) is open for business!")
                dismiss()
            } else {
                onToast("Need \(Format.currency(venue.unlockCost)) to open \(venue.name)")
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [palette.wallTop, palette.wallBottom],
                                             startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(palette.floor).frame(height: 16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Station 1 is each venue's signature dish and reads far better at this
                    // size than the abstract capstone platter.
                    FoodSprite(art: venue.stations[1].art, colors: venue.stations[1].colors)
                        .equatable()
                        .frame(width: 42, height: 42)
                        .saturation(unlocked ? 1 : 0)
                        .opacity(unlocked ? 1 : 0.5)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(venue.name)
                            .font(Theme.body(15, weight: .black))
                            .foregroundStyle(Theme.text)
                        if current {
                            Text("HERE")
                                .font(Theme.body(9, weight: .black))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(palette.accent))
                        }
                    }
                    Text(venue.tagline)
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)

                    if unlocked {
                        Text("\(staffedCount(venue)) of \(venue.stations.count) stations staffed")
                            .font(Theme.body(10, weight: .bold))
                            .foregroundStyle(Theme.positive)
                    } else {
                        Text("Dishes worth ×\(Format.currency(venue.revenueMultiplier)) more")
                            .font(Theme.body(10, weight: .bold))
                            .foregroundStyle(Theme.coin)
                    }
                }

                Spacer(minLength: 0)

                if !unlocked {
                    VStack(spacing: 2) {
                        Image(systemName: affordable ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 13, weight: .black))
                        Text(Format.currency(venue.unlockCost))
                            .font(Theme.numeric(12))
                    }
                    .foregroundStyle(affordable ? Theme.coin : Theme.textDim)
                }
            }
            .padding(12)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: current ? Theme.panelRaised : Theme.panel,
            shadow: Theme.ink,
            disabled: !unlocked && !affordable
        ))
    }

    private func staffedCount(_ venue: VenueSpec) -> Int {
        engine.state.venues[venue.id].stations.filter { $0.isStaffed }.count
    }
}
