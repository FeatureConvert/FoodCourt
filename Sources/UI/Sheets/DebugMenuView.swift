import SwiftUI

/// Reached by long-pressing the HUD in debug builds. Time-gated features (daily streaks,
/// offline earnings, boost expiry) are otherwise impossible to exercise in one sitting.
struct DebugMenuView: View {
    @EnvironmentObject private var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("debugCardStyleVariant") private var cardStyleVariantRaw: String = CardStyleVariant.current.rawValue
    let onToast: (String) -> Void

    var body: some View {
        SheetScaffold(title: "Debug", subtitle: "Development build only") {
            SectionLabel(text: "Card style review")
            HStack(spacing: 8) {
                ForEach(CardStyleVariant.allCases) { variant in
                    Button {
                        cardStyleVariantRaw = variant.rawValue
                        onToast("Card style: \(variant.label)")
                    } label: {
                        Text(variant.label)
                            .font(Theme.body(11, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(ChunkyButtonStyle(
                        fill: cardStyleVariantRaw == variant.rawValue ? Theme.coin : Theme.panelRaised,
                        shadow: Theme.ink,
                        radius: 12
                    ))
                }
            }

            SectionLabel(text: "Gold Spatula")
            // Local to this device only (UserDefaults, not save data - see
            // GameEngine.goldSpatulaLuckBoostEnabled) - flip on once, on whichever specific
            // phone should get the nudge, and it stays on for that install.
            Toggle(isOn: Binding(
                get: { engine.goldSpatulaLuckBoostEnabled },
                set: { engine.goldSpatulaLuckBoostEnabled = $0 }
            )) {
                Text("Gold Spatula Luck (this device)")
                    .font(Theme.body(12, weight: .bold))
            }
            .tint(Theme.coin)

            SectionLabel(text: "Clock")
            Text("Offset applied: \(Format.duration(engine.state.timeOffset))")
                .font(Theme.body(12, weight: .bold))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                skipButton("+1h", hours: 1)
                skipButton("+8h", hours: 8)
                skipButton("+24h", hours: 24)
                skipButton("+48h", hours: 48)
            }

            SectionLabel(text: "Currency")
            HStack(spacing: 8) {
                grantButton("+1K coins") { engine.addCoins(1_000) }
                grantButton("+1M coins") { engine.addCoins(1_000_000) }
                grantButton("+1B coins") { engine.addCoins(1_000_000_000) }
            }
            HStack(spacing: 8) {
                grantButton("+500 gems") { engine.addGems(500) }
                grantButton("+1T coins") { engine.addCoins(1e12) }
                grantButton("Staff all") { engine.grantManagerPack(venue: engine.state.currentVenue) }
            }
            HStack(spacing: 8) {
                // One-shot, same as every button in this menu - no toggle, no on/off
                // indicator anywhere afterward. See Balance.deviceProfitBoostDefaultsKey.
                grantButton("Profit boost") { engine.deviceProfitBoostEnabled = true }
            }

            SectionLabel(text: "Systems")
            HStack(spacing: 8) {
                grantButton("+2K tickets") { engine.awardTickets(2_000) }
                grantButton("Finish goals") { engine.debugCompleteQuests() }
                grantButton("End league") { engine.debugEndLeagueWeek() }
            }
            HStack(spacing: 8) {
                grantButton("Rush now") { engine.startRush(force: true) }
                grantButton("Epic staff") { _ = engine.grantManager(rarity: .epic) }
                grantButton("Legend staff") { _ = engine.grantManager(rarity: .legendary) }
            }
            HStack(spacing: 8) {
                grantButton("Unlock board") { engine.debugUnlockAllVenuesAndStations() }
                grantButton("Force prestige") {
                    // prestige() itself now guards on every venue and station being open,
                    // same as a real player - bypass it here the same way this menu bypasses
                    // every other real requirement.
                    engine.debugUnlockAllVenuesAndStations()
                    _ = engine.prestige()
                }
                grantButton("Force order") {
                    var attempts = 0
                    while engine.activeOrder == nil && attempts < 500 {
                        engine.rollStationOrder()
                        attempts += 1
                    }
                }
            }
            HStack(spacing: 8) {
                grantButton("+1 voucher") { engine.debugGrantFranchiseVoucher() }
            }

            SectionLabel(text: "State")
            Button {
                engine.save()
                onToast("Saved to \(SaveManager.fileURL.lastPathComponent)")
            } label: {
                wide("Force save")
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))

            Button {
                engine.debugReset()
                onToast("Save wiped")
                dismiss()
            } label: {
                wide("Wipe save & restart")
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.negative, shadow: Theme.ink))
        }
    }

    private func skipButton(_ title: String, hours: Double) -> some View {
        Button {
            engine.debugSkip(hours: hours)
            onToast("Clock advanced \(Format.duration(hours * 3600))")
            // Close so the welcome-back sheet has somewhere to present.
            dismiss()
        } label: {
            Text(title)
                .font(Theme.body(12, weight: .black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.gemDeep, shadow: Theme.ink, radius: 12))
    }

    private func grantButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onToast(title)
        } label: {
            Text(title)
                .font(Theme.body(11, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink, radius: 12))
    }

    private func wide(_ title: String) -> some View {
        Text(title)
            .font(Theme.body(13, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
    }
}
