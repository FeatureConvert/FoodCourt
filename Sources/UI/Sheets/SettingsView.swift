import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var cloud: CloudSaveService
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var sound: SoundService
    let onToast: (String) -> Void
    var onHelp: () -> Void = {}

    @State private var confirmingReset = false
    @State private var resetConfirmationText = ""
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("soundEnabled") private var soundEnabled = true

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

            IntroBanner(key: IntroKey.icloudSync, symbol: "icloud.fill",
                        title: "Your save follows your iCloud",
                        detail: "Signed into iCloud, your empire syncs across devices automatically and survives a reinstall. If another device is further along, the game always asks before touching this one's progress.")
            SectionLabel(text: "iCloud")
            VStack(spacing: 0) {
                row("Sync", cloud.status.label)
            }
            .panel(Theme.panel)

            if cloud.isAvailable {
                Button {
                    if engine.pushToCloud() {
                        Haptics.success()
                        sound.play(.reward)
                        onToast("Synced to iCloud")
                    } else {
                        Haptics.error()
                        sound.play(.denied)
                        onToast("Sync failed - check your iCloud connection and try again")
                    }
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

            SectionLabel(text: "Sound")
            Toggle(isOn: Binding(
                get: { soundEnabled },
                set: { on in
                    soundEnabled = on
                    if on { sound.play(.tap) }
                }
            )) {
                Text("Sound effects")
                    .font(Theme.body(13, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .panel(Theme.panel)

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
                label(store.isRestoring ? "Restoring..." : "Restore Purchases", system: "arrow.clockwise")
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
            .disabled(store.isRestoring)

            SectionLabel(text: "Danger zone")
            if confirmingReset {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This permanently erases every station, star, and gem on this device. There is no undo.")
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)

                    Text("Type RESET to confirm")
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.text)
                    TextField("RESET", text: $resetConfirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(Theme.numeric(15))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.ink.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1))

                    HStack(spacing: 10) {
                        Button {
                            confirmingReset = false
                            resetConfirmationText = ""
                        } label: {
                            Text("Cancel")
                                .font(Theme.body(13, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))

                        Button {
                            engine.debugReset()
                            cloud.wipeRemote()
                            onToast("Save wiped - fresh start")
                            confirmingReset = false
                            resetConfirmationText = ""
                        } label: {
                            Text("Erase everything")
                                .font(Theme.body(13, weight: .black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(ChunkyButtonStyle(fill: Theme.negative, shadow: Theme.negative.opacity(0.5)))
                        .disabled(resetConfirmationText.uppercased() != "RESET")
                        .opacity(resetConfirmationText.uppercased() != "RESET" ? 0.5 : 1)
                    }
                }
                .padding(12)
                .panel(Theme.panel)
            } else {
                Button {
                    confirmingReset = true
                } label: {
                    label("Reset progress", system: "trash.fill")
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
            }

            // App Review Guideline 5.1.1: an app with IAP + iCloud + Game Center must link
            // a privacy policy. The URL constant below is a placeholder Robert swaps for
            // the real hosted policy (and pastes into App Store Connect) before submission.
            Link(destination: Self.privacyPolicyURL) {
                Text("Privacy Policy")
                    .font(Theme.body(11, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .underline()
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
            .accessibilityLabel("Privacy Policy")

            Text("Food Court Tycoon · v1.0")
                .font(Theme.body(10, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    /// PLACEHOLDER - replace with the real hosted policy URL before App Store submission,
    /// and enter the same URL in App Store Connect's App Privacy section.
    static let privacyPolicyURL = URL(string: "https://example.com/foodcourttycoon/privacy")!

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
