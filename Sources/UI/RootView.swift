import SwiftUI

enum ActiveSheet: Identifiable, Equatable {
    case shop, venues, prestige, settings, debug, offline, collection, help
    case quests(QuestsView.Tab)
    case cloudConflict
    case daily
    case events(EventsView.Tab)
    case perk(Int)
    case cosmetics(Int)

    var id: String {
        switch self {
        case .shop: return "shop"
        case .venues: return "venues"
        case .prestige: return "prestige"
        case .settings: return "settings"
        case .debug: return "debug"
        case .offline: return "offline"
        case .collection: return "collection"
        case .quests(let tab): return "quests-\(tab.rawValue)"
        case .help: return "help"
        case .cloudConflict: return "cloud-conflict"
        case .daily: return "daily"
        case .events(let tab): return "events-\(tab.rawValue)"
        case .perk(let station): return "perk-\(station)"
        case .cosmetics(let venue): return "cosmetics-\(venue)"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var cloud: CloudSaveService

    @State private var sheet: ActiveSheet?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var hasHandledLaunch = false
    @State private var lastPresented: ActiveSheet?

    private var palette: VenuePalette {
        VenuePalette.of(Balance.venue(engine.state.currentVenue).theme)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.wallTop, palette.wallBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                HUDView(onDebug: { present(.debug) },
                        onSettings: { present(.settings) },
                        onStars: { present(.prestige) },
                        onHelp: { present(.help) })
                    .padding(.horizontal, 14)

                if engine.rushActive {
                    RushBannerView()
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ZStack(alignment: .topTrailing) {
                    VenueStageView(onGolden: { amount in
                        showToast("VIP tipped \(Format.currency(amount))!")
                    }, onCustomize: { present(.cosmetics(engine.state.currentVenue)) })
                    StageActionsView(onBoost: takeCoffeeBreak, onRush: startRush)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                }
                .padding(.horizontal, 14)

                ComboMeterView()
                    .padding(.horizontal, 14)

                StationListView(onToast: showToast,
                                onChoosePerk: { present(.perk($0)) })

                BottomBar(
                    onVenues: { present(.venues) },
                    onCollection: { present(.collection) },
                    onQuests: {
                        engine.completeTutorialStep(.openGoals)
                        // The Goals badge can be lit by a claimable quest, a claimable
                        // achievement, or both - open straight to whichever one is actually
                        // waiting rather than always landing on Quests with no clue the
                        // notification was really on the Achievements side.
                        let initialTab: QuestsView.Tab =
                            (engine.claimableQuests == 0 && !engine.claimableAchievements.isEmpty)
                            ? .achievements : .quests
                        present(.quests(initialTab))
                    },
                    onEvents: { present(.events(defaultEventsTab)) },
                    onShop: { present(.shop) }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            TutorialOverlay(onSkip: { engine.skipTutorial() })

            if let toast {
                ToastView(message: toast)
                    .padding(.bottom, 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: engine.state.tutorial.step)
        .animation(.easeInOut(duration: 0.25), value: engine.state.tutorial.finished)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: engine.rushActive)
        .sheet(item: $sheet, onDismiss: handleSheetDismissed) { which in
            sheetContent(for: which)
                .presentationDetents(detents(for: which))
                .presentationDragIndicator(.visible)
        }
        .onChange(of: sheet) { _, new in if let new { lastPresented = new } }
        .onChange(of: cloud.conflict) { _, conflict in
            if conflict != nil { present(.cloudConflict) }
        }
        .onChange(of: engine.pendingOfflineReport) { _, report in
            if report != nil { present(.offline) }
        }
        .onChange(of: engine.pendingPerkStation) { _, station in
            if let station { present(.perk(station)) }
        }
        .onChange(of: engine.pendingLeagueOutcome) { _, outcome in
            if let outcome { showToast(outcome.headline) }
        }
        .onChange(of: engine.lastRecipeDrop) { _, drop in
            if let drop { announce(drop) }
        }
        .onChange(of: engine.toast) { _, message in
            if let message { showToast(message); engine.toast = nil }
        }
        .onChange(of: store.lastGrant) { _, new in if let new { showToast(new) } }
        .onChange(of: store.errorMessage) { _, new in if let new { showToast(new) } }
        .onChange(of: engine.shouldNudgePrestige) { _, nudge in
            if nudge { announcePrestigeNudge() }
        }
        .onAppear(perform: handleLaunch)
        .preferredColorScheme(.dark)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(for which: ActiveSheet) -> some View {
        switch which {
        case .shop: ShopView(onToast: showToast)
        case .venues: VenueSelectView(onToast: showToast)
        case .prestige: PrestigeView(onToast: showToast)
        case .settings: SettingsView(onToast: showToast, onHelp: { present(.help) })
        case .debug: DebugMenuView(onToast: showToast)
        case .collection: CollectionView(onToast: showToast)
        case .quests(let tab): QuestsView(initialTab: tab, onToast: showToast)
        case .help: HelpView(onToast: showToast)
        case .cloudConflict:
            if let remote = cloud.conflict {
                CloudConflictView(remote: remote, onToast: showToast)
            }
        case .daily: DailyRewardView(onToast: showToast)
        case .events(let tab): EventsView(initialTab: tab, onToast: showToast)
        case .perk(let station): PerkChoiceView(station: station, onToast: showToast)
        case .offline:
            if let report = engine.pendingOfflineReport {
                OfflineEarningsView(report: report)
            }
        case .cosmetics(let venue): CosmeticsView(venue: venue, onToast: showToast)
        }
    }

    private func detents(for sheet: ActiveSheet) -> Set<PresentationDetent> {
        switch sheet {
        // .daily's content (7-day grid + claim button + streak explainer + streak row) is
        // consistently taller than .medium, which left the claim button sitting at the fold
        // with nothing below it hinting there was more to scroll to.
        case .venues, .collection, .events, .cloudConflict, .daily: return [.large]
        case .perk: return [.medium, .large]
        default: return [.medium, .large]
        }
    }

    /// Presenting while another sheet is still animating out gets dropped, so anything
    /// already showing is dismissed first and the new one follows.
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
        if lastPresented == .offline { engine.pendingOfflineReport = nil }
        if case .perk = lastPresented { engine.pendingPerkStation = nil }
    }

    private var defaultEventsTab: EventsView.Tab {
        if engine.dailyAvailable { return .daily }
        if Festival.unclaimedCount(engine.state.festival,
                                   premiumActive: engine.festivalPremiumActive) > 0 { return .festival }
        return .league
    }

    private func handleLaunch() {
        guard !hasHandledLaunch else { return }
        hasHandledLaunch = true

        if cloud.conflict != nil {
            present(.cloudConflict)
            return
        }
        if engine.pendingOfflineReport != nil {
            present(.offline)
            return
        }
        if engine.dailyAvailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { present(.daily) }
        } else if engine.shouldNudgePrestige {
            // Only when there's no daily-reward sheet also queued up for this launch - two
            // attention-grabbers landing on top of each other is worse than just letting the
            // star pill's persistent highlight (HUDView) do the reminding this time.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { announcePrestigeNudge() }
        }
    }

    /// A player can plausibly not know prestige exists the first time they're eligible, or
    /// forget it does once they've plateaued on a fully-built board again later - `engine.
    /// shouldNudgePrestige` (GameEngine.swift) covers both. The star pill's pulsing ring
    /// (HUDView) is the persistent version of this; the toast is the one-shot version fired
    /// only on the moment it becomes true.
    private func announcePrestigeNudge() {
        if engine.state.prestigeCount == 0 {
            showToast("You've earned enough to prestige! Tap the star for a permanent profit boost.")
        } else {
            showToast("Nothing left to build here — prestige again for another permanent boost.")
        }
    }

    // MARK: Actions

    /// No ads in this game - the boost is simply free on a cooldown.
    private func takeCoffeeBreak() {
        guard engine.claimFreeBoost() else {
            // A player who tapped this before the tutorial reached this step already showed
            // they know it - the boost being on cooldown from that earlier tap shouldn't
            // strand the tutorial for the rest of the wait.
            if engine.state.tutorial.current == .coffeeBreak {
                engine.completeTutorialStep(.coffeeBreak)
            }
            showToast("Coffee Break ready in \(Format.clock(engine.boostCooldownRemaining))")
            return
        }
        Haptics.success()
        showToast("Coffee Break! ×\(Format.trim(ActivePlay.freeBoostMultiplier)) for \(Int(ActivePlay.freeBoostHours * 60)) minutes")
    }

    private func startRush() {
        if engine.rushActive {
            showToast("Rush Hour already running")
        } else if engine.startRush() {
            Haptics.success()
            showToast("Rush Hour! ×\(Format.trim(ActivePlay.rushMultiplier)) for \(Format.duration(engine.state.rushDuration))")
        } else if engine.spendGems(ActivePlay.rushGemCost) {
            engine.startRush(force: true)
            Haptics.success()
            showToast("Rush Hour started early")
        } else {
            showToast("Ready in \(Format.clock(engine.rushCooldownRemaining)) · or \(ActivePlay.rushGemCost) gems")
        }
    }

    private func announce(_ drop: Recipes.Drop) {
        switch drop {
        case .none: return
        case .newCard(let venue, let station):
            showToast("Recipe found: \(Balance.venue(venue).stations[station].name)")
        case .upgraded(let venue, let station, let stars):
            showToast("\(Balance.venue(venue).stations[station].name) recipe → \(stars)★")
        case .duplicateGems(let gems):
            showToast("Duplicate recipe → +\(gems) gems")
        }
        engine.objectWillChange.send()
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

    let onVenues: () -> Void
    let onCollection: () -> Void
    let onQuests: () -> Void
    let onEvents: () -> Void
    let onShop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            barButton("Venues", "map.fill",
                      badge: engine.nextLockedVenue.map { engine.canUnlock($0) } == true,
                      action: onVenues)
            barButton("Staff", "person.2.fill",
                      badge: !engine.state.unassignedManagers.isEmpty || !engine.claimableErrands.isEmpty,
                      action: onCollection)
            barButton("Goals", "checklist",
                      badge: engine.claimableQuests > 0 || !engine.claimableAchievements.isEmpty,
                      target: .goalsTab, action: onQuests)
            barButton("Events", "calendar",
                      badge: eventsBadge, action: onEvents)
            barButton("Shop", "cart.fill", badge: false, action: onShop)
        }
    }

    private var eventsBadge: Bool {
        engine.dailyAvailable
            || Festival.unclaimedCount(engine.state.festival,
                                       premiumActive: engine.festivalPremiumActive) > 0
    }

    private func barButton(_ title: String, _ symbol: String, badge: Bool,
                           target: TutorialTarget? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    GlyphIcon(symbol, tint: Theme.text)
                        .frame(width: 19, height: 19)
                        .frame(height: 22)
                    if badge {
                        Circle().fill(Theme.negative)
                            .frame(width: 9, height: 9)
                            .offset(x: 7, y: -3)
                    }
                }
                Text(title)
                    .font(Theme.body(10, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink))
        .tutorialHighlight(target)
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(Theme.body(14, weight: .bold))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .panel(Theme.panelRaised, radius: 14)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            .padding(.horizontal, 24)
    }
}
