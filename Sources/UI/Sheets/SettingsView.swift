import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var cloud: CloudSaveService
    @EnvironmentObject private var notifications: NotificationService
    let onToast: (String) -> Void
    var onHelp: () -> Void = {}

    @State private var confirmingReset = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    var body: some View {
        SheetScaffold(title: "Settings") {
            AdFreeBadge()

            SectionLabel(text: "Progress")
            VStack(spacing: 0) {
                row("Lifetime earnings", Format.currency(engine.state.lifetimeEarnings))
                row("Franchise stars", Format.count(engine.state.stars))
                row("Venues open", "\(engine.state.venues.filter(\.self.unlocked).count) of \(Balance.venues.count)")
                row("Offline cap", "\(Format.trim(engine.state.offlineCapHours))h")
                row("Ads shown", "0")
            }
            .panel(Theme.panel)

            SectionLabel(text: "iCloud")
            VStack(spacing: 0) {
                row("Sync", cloud.status.label)
            }
            .panel(Theme.panel)

            if cloud.isAvailable {
                Button {
                    engine.pushToCloud()
                    onToast("Saved to iCloud")
                } label: {
                    label("Sync now", system: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
            } else {
                Text("Sign in to iCloud to keep your progress across devices. Until then it is stored on this device only.")
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionLabel(text: "Notifications")
            Toggle(isOn: Binding(
                get: { notificationsEnabled },
                set: { on in
                    notificationsEnabled = on
                    if on { notifications.requestAuthorizationIfNeeded() } else { notifications.cancelAll() }
                }
            )) {
                Text("Reminders")
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .panel(Theme.panel)
            Text("Rush Hour ready, offline earnings capped, and festival/league deadlines - only while the app is closed.")
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            SectionLabel(text: "Help")
            Button {
                onHelp()
            } label: {
                label("Guide & FAQ", system: "questionmark.circle.fill")
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))

            SectionLabel(text: "Purchases")
            Button {
                Task { await store.restore() }
            } label: {
                label("Restore Purchases", system: "arrow.clockwise")
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))

            SectionLabel(text: "Danger zone")
            Button {
                if confirmingReset {
                    engine.debugReset()
                    onToast("Save wiped - fresh start")
                    confirmingReset = false
                } else {
                    confirmingReset = true
                }
            } label: {
                label(confirmingReset ? "Tap again to erase everything" : "Reset progress",
                      system: "trash.fill")
            }
            .buttonStyle(ChunkyButtonStyle(fill: confirmingReset ? Theme.negative : Theme.panelRaised,
                                           shadow: Theme.ink))

            Text("Food Court Tycoon · v1.0")
                .font(Theme.body(10, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(Theme.body(12, weight: .medium)).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value).font(Theme.numeric(13)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func label(_ title: String, system: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: system).font(.system(size: 13, weight: .bold))
            Text(title).font(Theme.body(13, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
