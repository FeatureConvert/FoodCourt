import SwiftUI

enum ActiveSheet: String, Identifiable {
    case shop, daily, venues, prestige, settings, debug, offline
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var ads: AdService

    @State private var sheet: ActiveSheet?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var hasOfferedDaily = false
    /// `onDismiss` doesn't say which sheet closed, so remember the last one presented.
    @State private var lastPresented: ActiveSheet?

    private var palette: VenuePalette {
        VenuePalette.of(Balance.venue(engine.state.currentVenue).theme)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.wallTop, palette.wallBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HUDView(onDebug: { sheet = .debug }, onSettings: { sheet = .settings })
                    .padding(.horizontal, 14)

                VenueStageView()
                    .padding(.horizontal, 14)

                StationListView(onToast: showToast)

                BottomBar(
                    onShop: { sheet = .shop },
                    onDaily: { sheet = .daily },
                    onVenues: { sheet = .venues },
                    onPrestige: { sheet = .prestige },
                    onBoost: watchAd
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            if ads.isPlaying {
                AdOverlayView().transition(.opacity)
            }

            if let toast {
                ToastView(message: toast)
                    .padding(.bottom, 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
        .animation(.easeInOut(duration: 0.2), value: ads.isPlaying)
        // One sheet modifier, one source of truth. Two competing `.sheet` modifiers race
        // when one dismisses as the other presents, and SwiftUI silently drops the second.
        .sheet(item: $sheet, onDismiss: handleSheetDismissed) { which in
            sheetContent(for: which)
                .presentationDetents(which == .venues ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: sheet) { _, new in
            if let new { lastPresented = new }
        }
        .onChange(of: engine.pendingOfflineReport) { _, report in
            if report != nil { present(.offline) }
        }
        .onAppear(perform: handleLaunch)
        .onChange(of: store.lastGrant) { _, new in if let new { showToast(new) } }
        .onChange(of: store.errorMessage) { _, new in if let new { showToast(new) } }
        .onChange(of: ads.lastReward) { _, new in if let new { showToast(new) } }
        .preferredColorScheme(.dark)
    }

    // MARK: Pieces

    @ViewBuilder
    private func sheetContent(for which: ActiveSheet) -> some View {
        switch which {
        case .shop: ShopView(onToast: showToast)
        case .daily: DailyRewardView(onToast: showToast)
        case .venues: VenueSelectView(onToast: showToast)
        case .prestige: PrestigeView(onToast: showToast)
        case .settings: SettingsView(onToast: showToast)
        case .debug: DebugMenuView(onToast: showToast)
        case .offline:
            if let report = engine.pendingOfflineReport {
                OfflineEarningsView(report: report)
            }
        }
    }

    /// Swaps sheets safely. Presenting while another sheet is still animating out gets
    /// dropped, so anything already showing is dismissed first and the new one follows.
    private func present(_ next: ActiveSheet) {
        guard sheet != next else { return }
        if sheet == nil {
            sheet = next
        } else {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet = next }
        }
    }

    private func handleSheetDismissed() {
        // Only the welcome-back screen consumes the report. Clearing it on any dismissal
        // would wipe a report that was raised while a different sheet happened to be open.
        guard lastPresented == .offline else { return }
        engine.pendingOfflineReport = nil
    }

    private func handleLaunch() {
        guard !hasOfferedDaily else { return }
        hasOfferedDaily = true

        if engine.pendingOfflineReport != nil {
            present(.offline)
            return
        }
        // The calendar is the first thing a returning player should see, but not on top of
        // a welcome-back payout.
        guard engine.dailyAvailable else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { present(.daily) }
    }

    private func watchAd() {
        guard engine.adReady else {
            showToast("Next free boost in \(Format.clock(engine.adCooldownRemaining))")
            return
        }
        Haptics.tap()
        ads.play(engine: engine)
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    @EnvironmentObject private var engine: GameEngine

    let onShop: () -> Void
    let onDaily: () -> Void
    let onVenues: () -> Void
    let onPrestige: () -> Void
    let onBoost: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            barButton("Venues", "map.fill", badge: engine.nextLockedVenue.map { engine.canUnlock($0) } == true,
                      action: onVenues)
            barButton("Boost", "bolt.fill", badge: engine.adReady, action: onBoost)
            barButton("Daily", "gift.fill", badge: engine.dailyAvailable, action: onDaily)
            barButton("Shop", "cart.fill", badge: false, action: onShop)
            barButton("Franchise", "star.fill", badge: engine.canPrestige, action: onPrestige)
        }
    }

    private func barButton(_ title: String, _ symbol: String, badge: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .bold))
                        .frame(height: 22)
                    if badge {
                        Circle()
                            .fill(Theme.negative)
                            .frame(width: 9, height: 9)
                            .offset(x: 7, y: -3)
                    }
                }
                Text(title)
                    .font(Theme.body(10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(Theme.body(14, weight: .bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .panel(Theme.panelRaised, radius: 14)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .padding(.horizontal, 24)
    }
}
