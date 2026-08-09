import SwiftUI

struct ShopView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void

    var body: some View {
        SheetScaffold(title: "Shop", subtitle: "Gems keep the kitchen moving") {
            AdFreeBadge()

            SectionLabel(text: "Today's deal")
            dailyDealRow

            SectionLabel(text: "Spend gems")
            ForEach(GemOffer.allSortedByCost) { offer in
                gemSinkRow(offer)
            }

            SectionLabel(text: "Special offers")
            ForEach(ShopCatalog.offers) { item in
                iapRow(item, wide: true)
            }

            SectionLabel(text: "Gem packs")
            ForEach(ShopCatalog.gemPacks) { item in
                iapRow(item, wide: false)
            }

            Button {
                Task { await store.restore() }
            } label: {
                Text("Restore Purchases")
                    .font(Theme.body(13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
            .padding(.top, 8)

            Text("Nothing here is required to finish the game. Purchases are billed to your Apple Account. Gems are a virtual currency with no cash value.")
                .font(Theme.body(10, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .task {
            await store.loadProducts()
        }
    }

    // MARK: Rows

    /// The rotating 30%-off sink - same row as any other, wrapped with the deal framing
    /// (badge, struck-through regular price). Rotates by calendar day; see
    /// `GemOffer.dailyDeal`.
    private var dailyDealRow: some View {
        let deal = GemOffer.dailyDeal(now: engine.state.now)
        let regular = GemOffer.all.first { $0.id == deal.id }?.cost ?? deal.cost
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("DAILY DEAL · 30% OFF")
                    .font(Theme.body(9, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.positive))
                Text("was \(regular)")
                    .font(Theme.body(10, weight: .bold))
                    .strikethrough()
                    .foregroundStyle(Theme.textDim)
                Spacer(minLength: 0)
                Text("new deal tomorrow")
                    .font(Theme.body(9, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            gemSinkRow(deal)
        }
    }

    private func gemSinkRow(_ offer: GemOffer) -> some View {
        let affordable = engine.state.gems >= offer.cost
        return Button {
            switch GemSpend.redeem(offer, engine: engine) {
            case .success(let message):
                Haptics.success()
                sound.play(.reward)
                onToast(message)
            case .insufficientGems:
                sound.play(.denied)
                onToast("Not enough gems")
            case .nothingToDo(let message):
                onToast(message)
            }
        } label: {
            HStack(spacing: 12) {
                GlyphIcon(offer.symbol, tint: Theme.gem)
                    .frame(width: 21, height: 21)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.title)
                        .font(Theme.body(14, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text(offer.subtitle)
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    GemIcon().frame(width: 15, height: 15)
                    Text("\(offer.cost)")
                        .font(Theme.numeric(14))
                }
                .foregroundStyle(affordable ? Theme.text : Theme.textDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(affordable ? Theme.gemDeep : Theme.locked.opacity(0.5)))
            }
            .padding(12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panel, shadow: Theme.ink))
    }

    private func iapRow(_ item: ShopItem, wide: Bool) -> some View {
        let owned = store.isOwned(item)
        let busy = store.purchasingID == item.id

        return Button {
            Task { await store.purchase(item) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.ink.opacity(0.5))
                    gemPile(magnitude: item.magnitude)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(Theme.body(14, weight: .black))
                            .foregroundStyle(Theme.text)
                        if let badge = item.badge {
                            Text(badge)
                                .font(Theme.body(9, weight: .black))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.coin))
                        }
                    }
                    Text(item.subtitle)
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(wide ? 3 : 1)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)

                Group {
                    if owned {
                        Text("OWNED").font(Theme.body(11, weight: .black))
                            .foregroundStyle(Theme.positive)
                    } else if busy {
                        ProgressView().tint(Theme.text)
                    } else {
                        Text(store.displayPrice(for: item))
                            .font(Theme.numeric(14))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Theme.coin))
                    }
                }
            }
            .padding(12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panel, shadow: Theme.ink, disabled: owned))
        .disabled(owned || busy)
    }

    /// A pile whose size tracks the pack, so the tiers read at a glance.
    private func gemPile(magnitude: Int) -> some View {
        ZStack {
            ForEach(0..<min(magnitude, 4), id: \.self) { index in
                GemIcon()
                    .frame(width: 20 - CGFloat(index) * 2, height: 20 - CGFloat(index) * 2)
                    .offset(x: CGFloat(index % 2 == 0 ? -index * 6 : index * 6),
                            y: CGFloat(index) * 4 - 4)
            }
        }
    }
}
