import SwiftUI

/// Shown when iCloud holds a save that is further along than this device's. Both options are
/// spelled out with their numbers, because silently picking one for the player means somebody
/// loses an empire without being told.
struct CloudConflictView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var cloud: CloudSaveService
    @Environment(\.dismiss) private var dismiss

    let remote: GameState
    let onToast: (String) -> Void

    // Same "tap again to confirm" pattern as the Legacy and Danger Zone resets - this is the
    // one screen in the app where a single mis-tap permanently deletes an empire, and it had
    // no safety net at all.
    @State private var confirmingCloud = false
    @State private var confirmingDevice = false

    var body: some View {
        SheetScaffold(title: "Two saves found",
                      subtitle: "iCloud has progress from another device") {
            saveCard(title: "On iCloud", state: remote, tint: Theme.gem, recommended: true)
            saveCard(title: "On this device", state: engine.state, tint: Theme.coin,
                     recommended: false)

            Button {
                if confirmingCloud {
                    engine.adoptCloudSave(remote)
                    cloud.conflict = nil
                    onToast("Loaded your iCloud save")
                    dismiss()
                } else {
                    confirmingCloud = true
                    confirmingDevice = false
                }
            } label: {
                Text(confirmingCloud ? "Tap again to confirm" : "Use the iCloud save")
                    .font(Theme.body(15, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(ChunkyButtonStyle(fill: confirmingCloud ? Theme.negative : Theme.gemDeep,
                                           shadow: Theme.ink))

            Button {
                // Keeping this device wins by pushing over the remote, so the two stop
                // fighting on the next launch.
                if confirmingDevice {
                    engine.pushToCloud()
                    cloud.conflict = nil
                    onToast("Kept this device's save")
                    dismiss()
                } else {
                    confirmingDevice = true
                    confirmingCloud = false
                }
            } label: {
                Text(confirmingDevice ? "Tap again to confirm" : "Keep this device")
                    .font(Theme.body(14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(ChunkyButtonStyle(fill: confirmingDevice ? Theme.negative : Theme.panelRaised,
                                           shadow: Theme.ink))

            Text("Whichever you keep replaces the other. This cannot be undone.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled(true)
    }

    private func saveCard(title: String, state: GameState, tint: Color,
                          recommended: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(tint)
                Spacer()
                if recommended {
                    Text("FURTHER ALONG")
                        .font(Theme.body(9, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(tint))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            row("Lifetime earnings", Format.currency(state.lifetimeEarnings))
            row("Franchise stars", Format.count(state.lifetimeStars))
            row("Venues open", "\(state.venues.filter(\.unlocked).count)")
            row("Staff", Format.count(state.managers.count))
            row("Recipe cards", Format.count(Recipes.totalCollected(state.recipeCards)))
        }
        .panel(Theme.panel)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.body(12, weight: .medium)).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value).font(Theme.numeric(13)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
