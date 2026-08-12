import SwiftUI

enum ActiveSheet: Identifiable, Equatable {
    case shop, venues, prestige, settings, debug, offline, collection, help
    case quests(QuestsView.Tab)
    case cloudConflict
    case daily
    case events(EventsView.Tab)
    case perk(Int)
    case cosmetics(Int)
    case welcome, prestigeIntro, legacyIntro
    case runRecap
    case contractChoice, legacyPerkChoice
    case toolDrop
    case flashSale

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
        case .welcome: return "welcome"
        case .prestigeIntro: return "prestige-intro"
        case .legacyIntro: return "legacy-intro"
        case .runRecap: return "run-recap"
        case .contractChoice: return "contract-choice"
        case .legacyPerkChoice: return "legacy-perk-choice"
        case .toolDrop: return "tool-drop"
        case .flashSale: return "flash-sale"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var cloud: CloudSaveService
    @EnvironmentObject private var sound: SoundService

    /// Distinguishes an iPad-sized canvas from an iPhone-sized one. Deliberately size class
    /// rather than `userInterfaceIdiom`: an iPad in Slide Over or a narrow Split View
    /// reports `.compact`, and at that width the phone layout genuinely is the right one -
    /// an idiom check would force the roomy layout into a column too narrow for it.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRoomy: Bool { horizontalSizeClass == .regular }

    @State private var sheet: ActiveSheet?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var hasHandledLaunch = false
    @State private var lastPresented: ActiveSheet?

    private var palette: VenuePalette {
        VenuePalette.of(Balance.venue(engine.state.currentVenue).theme)
    }

    // Split into three layers (content -> sheeted -> observed) purely for the
    // type-checker: the single-expression body grew past what Swift will infer in
    // reasonable time once the observer list passed a dozen entries.
    var body: some View { observedContent }

    private var mainContent: some View {
        ZStack {
            LinearGradient(colors: [palette.wallTop, palette.wallBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // iPhone is portrait-locked (see project.yml), so this only ever measures
            // landscape on iPad - width/height is the standard way to tell, since iPad
            // reports .regular for both size classes in full-screen regardless of
            // orientation and can't be used to distinguish them.
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    landscapeContent(width: geo.size.width)
                } else {
                    portraitContent(height: geo.size.height)
                }
            }

            TutorialOverlay(onSkip: { engine.skipTutorial() })

            if let toast {
                ToastView(message: toast)
                    .padding(.bottom, 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func stageOverlay(fixedHeight: CGFloat? = 168) -> some View {
        ZStack(alignment: .topTrailing) {
            VenueStageView(onGolden: { amount in
                showToast("VIP tipped \(Format.currency(amount))!")
            }, onCustomize: { present(.cosmetics(engine.state.currentVenue)) },
            fixedHeight: fixedHeight)
            StageActionsView(onBoost: takeCoffeeBreak, onRush: startRush)
                .padding(.top, 10)
                .padding(.trailing, 10)
        }
    }

    private func navBar(axis: Axis = .horizontal) -> BottomBar {
        BottomBar(
            axis: axis,
            onVenues: {
                engine.markIntroSeen(IntroKey.venueNudge)
                present(.venues)
            },
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
    }

    private func portraitContent(height: Double) -> some View {
        VStack(spacing: 8) {
            HUDView(onDebug: { present(.debug) },
                    onSettings: { present(.settings) },
                    onStars: { present(.prestige) },
                    onHelp: { present(.help) },
                    onBadgeInfo: showToast)
                .padding(.horizontal, 14)

            if engine.rushActive {
                RushBannerView()
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 168pt is a sensible slice of an iPhone screen but a thin band on an iPad, and
            // six stations over two columns only fill three rows - so the stations list runs
            // out well before the screen does, leaving a dead gap above the tab bar. Handing
            // the leftover height to the stage fixes both at once: the art gets room to
            // actually be looked at, and the column below it stops floating in empty space.
            // Proportional rather than a fixed number so it holds from an 11" iPad up to a
            // 13" one; the stage art is laid out in fractions of its own height, so it
            // scales rather than just growing empty floor.
            // Clamped, not purely proportional: the stage lays its parts out in fractions of
            // its own height, so past about 300pt the counter stops reading as a counter and
            // becomes a slab of flat colour across the bottom third. This range is the band
            // where the art still looks composed - the remaining slack above the tab bar is
            // the lesser evil.
            stageOverlay(fixedHeight: isRoomy ? min(300, max(240, height * 0.26)) : 168)
                .padding(.horizontal, 14)

            ComboMeterView()
                .padding(.horizontal, 14)

            // Two columns on an iPad-sized canvas. At one column a station row stretches the
            // full ~1300pt: name and level pinned far left, buy button pinned far right, and
            // a vast dead gap between them that the eye has to cross for every single row.
            // Halving the width puts the two ends back within one glance of each other, and
            // fills the vertical space with real content instead of padding.
            StationListView(onToast: showToast,
                            onChoosePerk: { present(.perk($0)) },
                            columns: isRoomy ? 2 : 1)

            navBar()
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
    }

    /// The stage gets a real column instead of a sliver above a scrolling list, and the
    /// bottom tab bar becomes a leading sidebar - the two changes that actually use the
    /// extra width, rather than just stretching the portrait stack sideways.
    private func landscapeContent(width: Double) -> some View {
        let sidebarWidth: Double = 92
        // 0.44 left every station card too narrow for 2 real columns after the fixed
        // sidebar and padding were subtracted; 0.36 was still tight enough that the level/
        // rate text (StationCardView's fixed 66pt cooker + 92pt actions leave little room
        // for the middle text column once split two-up) read cramped. 0.30 gives each card
        // roughly 30pt more width while the stage still holds a real, legible size at its
        // 2.4:1 aspect ratio.
        let stageColumnWidth = (width - sidebarWidth) * 0.30

        return HStack(spacing: 0) {
            navBar(axis: .vertical)
                .frame(width: sidebarWidth)
                .padding(.vertical, 14)

            VStack(spacing: 8) {
                HUDView(onDebug: { present(.debug) },
                        onSettings: { present(.settings) },
                        onStars: { present(.prestige) },
                        onHelp: { present(.help) },
                        onBadgeInfo: showToast)

                if engine.rushActive {
                    RushBannerView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Full width like the HUD above it, not squeezed into the narrow stage
                // column - at the stage column's ~36% width the bar read as oddly cramped
                // next to the much wider station grid it sits beside.
                ComboMeterView()

                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        // VenueProps' own doc comment: its art assumes "the stage strip is
                        // short and wide". Stretching the stage to fill this tall narrow
                        // column (maxHeight: .infinity, ~36% width) inverted that entirely -
                        // every prop stretched vertically, worst on the burger theme's menu
                        // board, which turned into an oversized dark blob. Capping the
                        // aspect ratio keeps every venue's art in the proportions it was
                        // actually drawn for; the leftover column height is just breathing
                        // room, not a deficiency to fill.
                        stageOverlay(fixedHeight: nil)
                            .aspectRatio(2.4, contentMode: .fit)
                        Spacer(minLength: 0)
                    }
                    .frame(width: stageColumnWidth)

                    StationListView(onToast: showToast,
                                    onChoosePerk: { present(.perk($0)) },
                                    columns: 2)
                }
            }
            .padding(.trailing, 14)
            .padding(.vertical, 8)
        }
    }

    private var sheetedContent: some View {
        mainContent
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: engine.state.tutorial.step)
            .animation(.easeInOut(duration: 0.25), value: engine.state.tutorial.finished)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: engine.rushActive)
            .sheet(item: $sheet, onDismiss: handleSheetDismissed) { which in
                sheetContent(for: which)
                    .presentationDetents(detents(for: which))
                    .presentationDragIndicator(.visible)
            }
    }

    private var gameplayObserved: some View {
        sheetedContent
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
        .onChange(of: engine.state.legacy.level) { old, new in
            // A fresh Legacy level owes its tree pick the moment the reset lands.
            guard new > old, engine.pendingLegacyPerkOffer != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { present(.legacyPerkChoice) }
        }
        .onChange(of: engine.lastRunRecap) { _, recap in
            // The celebration half of the prestige moment - the confirm sheet showed the
            // decision, this shows what the run WAS. Delayed so the prestige sheet's
            // dismissal finishes before a new sheet presents.
            guard recap != nil else { return }
            sound.play(.bigReward)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { present(.runRecap) }
        }
        .onChange(of: engine.pendingToolDrop) { _, tool in
            guard let tool else { return }
            if tool.rarity == .legendary {
                // The Gold Spatula moment - the rarest thing in the game gets the
                // biggest celebration in the game.
                sound.play(.bigReward)
                Haptics.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { present(.toolDrop) }
            } else {
                sound.play(.reward)
                showToast("\(tool.name) found! \(tool.detail)")
                engine.pendingToolDrop = nil
            }
        }
        .onChange(of: engine.pendingFlashSaleAnnouncement) { _, sale in
            guard sale != nil else { return }
            sound.play(.reward)
            Haptics.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { present(.flashSale) }
        }
        .onChange(of: engine.pendingLandmark) { _, landmark in
            guard let landmark else { return }
            sound.play(.bigReward)
            Haptics.success()
            showToast("LANDMARK: first time past \(Format.currency(landmark)) lifetime earnings!")
            engine.pendingLandmark = nil
        }
        .onChange(of: engine.halfwayToFirstFranchise) { _, halfway in
            // Late tutorial beat: name the "real game" the moment it's half in reach.
            guard halfway, !engine.hasSeenIntro(IntroKey.halfwayFranchise) else { return }
            engine.markIntroSeen(IntroKey.halfwayFranchise)
            showToast("Halfway to your first Franchise - the star pill is where the real game starts.")
        }
    }

    /// The moment a pacing gate opens mid-play, say so - the player shouldn't have to
    /// stumble onto a new system by revisiting a tab. One-shot per save; a gate that's
    /// already open at launch stays quiet (those players have met the system already).
    private var unlockObserved: some View {
        gameplayObserved
        .onChange(of: engine.state.tutorial.finished) { wasDone, done in
            // The weekly challenge deliberately waits for graduation (rolling it at first
            // launch snapshots a zero serve rate and mints a floor-sized target), so roll
            // it the moment the tutorial ends rather than on the next cold launch.
            if done, !wasDone { engine.rollWeeklyQuestIfNeeded() }
            // Graduation beat: the coach cards used to just... stop. Point at the system
            // that carries guidance from here. Fires for completion and skip alike.
            guard done, !wasDone, !engine.hasSeenIntro(IntroKey.tutorialDone) else { return }
            engine.markIntroSeen(IntroKey.tutorialDone)
            sound.play(.reward)
            showToast("That's the whole loop! Your NEXT GOAL chip up top takes it from here.")
        }
        .onChange(of: engine.crewsRelevant) { _, open in
            if open { announceUnlock(IntroKey.crewsUnlockToast,
                                     "New: Crews! Your named managers have chemistry - see the Staff tab.") }
        }
        .onChange(of: engine.faceOffsRelevant) { _, open in
            if open { announceUnlock(IntroKey.faceOffsUnlockToast,
                                     "New: Face-Offs! Send a bench crew to out-cook a rival - Staff → Errands.") }
        }
        .onChange(of: engine.gauntletRelevant) { _, open in
            if open { announceUnlock(IntroKey.gauntletUnlockToast,
                                     "New: the Weekly Gauntlet! A ten-minute scored sprint waits in Events.") }
        }
        .onChange(of: engine.toolsRelevant) { _, open in
            if open { announceUnlock(IntroKey.toolsUnlockToast,
                                     "New: Kitchen Tools! Rare drops from big moments - the shelf is in Recipes.") }
        }
    }

    private func announceUnlock(_ key: String, _ message: String) {
        guard !engine.hasSeenIntro(key) else { return }
        engine.markIntroSeen(key)
        sound.play(.reward)
        Haptics.success()
        showToast(message)
    }

    private var observedContent: some View {
        unlockObserved
        .onChange(of: engine.pendingLeagueOutcome) { _, outcome in
            if let outcome {
                switch outcome {
                case .promoted: sound.play(.bigReward)
                case .held: sound.play(.reward)
                case .relegated: sound.play(.denied)
                }
                showToast(outcome.headline)
            }
        }
        .onChange(of: engine.lastRecipeDrop) { _, drop in
            if let drop { announce(drop) }
        }
        .onChange(of: engine.toast) { _, message in
            if let message { showToast(message); engine.toast = nil }
        }
        .onChange(of: store.lastGrant) { _, new in
            if let new { sound.play(.bigReward); showToast(new) }
        }
        .onChange(of: store.errorMessage) { _, new in
            if let new { sound.play(.denied); showToast(new) }
        }
        .onChange(of: engine.shouldNudgePrestige) { _, nudge in
            if nudge { announcePrestigeNudge() }
        }
        .onChange(of: engine.canLegacyReset) { _, ready in
            if ready && !engine.hasSeenIntro(IntroKey.legacy) { present(.legacyIntro) }
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
        case .daily: DailyRewardView(onToast: showToast, onNavigate: { present($0) })
        case .events(let tab): EventsView(initialTab: tab, onToast: showToast)
        case .perk(let station): PerkChoiceView(station: station, onToast: showToast)
        case .offline:
            if let report = engine.pendingOfflineReport {
                OfflineEarningsView(report: report, onToast: showToast)
            }
        case .cosmetics(let venue): CosmeticsView(venue: venue, onToast: showToast)
        case .welcome: WelcomeView()
        case .prestigeIntro:
            BigMomentAlertView(
                symbol: "star.fill",
                headline: "Your First Franchise",
                detail: "You've earned enough to franchise out: cash in this run for permanent Stars, then start over with a lasting profit boost that never goes away. Recipes, research, and your top-tier staff carry over.",
                stat: (label: "Stars waiting", value: "+\(engine.pendingStars)"),
                ctaTitle: "See the Franchise",
                onCTA: { present(.prestige) }
            )
        case .runRecap:
            if let recap = engine.lastRunRecap {
                BigMomentAlertView(
                    symbol: "star.fill",
                    headline: "Franchise #\(recap.prestigeNumber) Complete",
                    detail: recapDetail(recap),
                    stat: (label: "Stars won", value: "+\(Format.count(recap.starsAwarded))"),
                    ctaTitle: engine.pendingContractOffer != nil
                        ? "Choose your Contract" : "Spend them on Research",
                    onCTA: {
                        present(engine.pendingContractOffer != nil ? .contractChoice : .prestige)
                    }
                )
            }
        case .contractChoice: ContractChoiceView(onToast: showToast)
        case .legacyPerkChoice: LegacyPerkChoiceView(onToast: showToast)
        case .toolDrop:
            if let tool = engine.pendingToolDrop {
                BigMomentAlertView(
                    symbol: tool.symbol,
                    headline: "\(tool.name) Found!",
                    detail: "A \(tool.rarity.label.lowercased()) kitchen tool - \(tool.detail). Tools are permanent: no slots, no upkeep, just yours. The collection lives in the Recipes tab.",
                    stat: (label: "Rarity", value: tool.rarity.label),
                    ctaTitle: "Beautiful",
                    onCTA: { engine.pendingToolDrop = nil }
                )
            }
        case .legacyIntro:
            BigMomentAlertView(
                symbol: "crown.fill",
                headline: "Legacy Unlocked",
                detail: "Five franchises in, a Legacy reset is now open to you: trade away your star bonus and earnings history to start the climb again with a permanently bigger multiplier. Research, recipes, tools, and staff are yours forever. Optional and one-way - usually worth waiting until your star bonus has slowed down.",
                stat: (label: "Lifetime stars", value: "\(engine.state.lifetimeStars)"),
                ctaTitle: "See Legacy",
                onCTA: { present(.prestige) }
            )
        case .flashSale:
            if let sale = engine.state.flashSale {
                BigMomentAlertView(
                    symbol: "bolt.fill",
                    headline: "Flash Sale!",
                    detail: "For the next \(Format.duration(sale.expiresAt.timeIntervalSince(engine.state.now))), the Pouch pays out \(Format.count(sale.bonusGems)) gems instead of \(Format.count(FlashSaleKit.baseGems)) - same price, bonus gems. Ends the moment the timer runs out.",
                    stat: (label: "Bonus gems", value: "+\(Format.count(sale.bonusGems - FlashSaleKit.baseGems))"),
                    ctaTitle: "See the Deal",
                    onCTA: { present(.shop) }
                )
            }
        }
    }

    private func detents(for sheet: ActiveSheet) -> Set<PresentationDetent> {
        switch sheet {
        // .daily's content (7-day grid + claim button + streak explainer + streak row) is
        // consistently taller than .medium, which left the claim button sitting at the fold
        // with nothing below it hinting there was more to scroll to. .quests (Goals/
        // Achievements) is the same story, worse on iPad where a .medium detent leaves even
        // more of the list needing a scroll to reach.
        case .venues, .collection, .events, .cloudConflict, .daily, .quests, .perk,
             .welcome, .prestigeIntro, .legacyIntro:
            return [.large]
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
        // Marked seen on dismiss rather than the moment each sheet is presented, so an app
        // kill mid-alert doesn't burn the one-shot before the player ever actually saw it.
        if lastPresented == .welcome { engine.markIntroSeen(IntroKey.welcome) }
        if lastPresented == .prestigeIntro { engine.markIntroSeen(IntroKey.prestige) }
        if lastPresented == .legacyIntro { engine.markIntroSeen(IntroKey.legacy) }
        if lastPresented == .flashSale { engine.pendingFlashSaleAnnouncement = nil }
    }

    private var defaultEventsTab: EventsView.Tab {
        if engine.dailyAvailable { return .daily }
        if Festival.unclaimedCount(engine.state.festival,
                                   premiumActive: engine.festivalPremiumActive) > 0 { return .festival }
        return .league
    }

    private func recapDetail(_ recap: RunRecap) -> String {
        var text = "This run: \(Format.duration(recap.duration)) · \(Format.currency(recap.earned)) earned · \(Format.count(recap.served)) dishes served."
        if recap.prestigeNumber == 1 {
            text += " Stars never reset. Research never sleeps. Go again, bigger."
        }
        return text
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
        if !engine.hasSeenIntro(IntroKey.welcome) {
            // A brand new save also has a daily reward waiting on day one - the welcome
            // screen matters more the first time, so it goes first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { present(.welcome) }
        } else if engine.pendingLegacyPerkOffer != nil {
            // Owed picks come before anything else on launch - a Legacy level without its
            // perk, or a run without its contract, is a decision left dangling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { present(.legacyPerkChoice) }
        } else if engine.pendingContractOffer != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { present(.contractChoice) }
        } else if engine.dailyAvailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { present(.daily) }
        } else if engine.canLegacyReset && !engine.hasSeenIntro(IntroKey.legacy) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { present(.legacyIntro) }
        } else if engine.shouldNudgePrestige {
            // Only when nothing else is already queued up for this launch - two
            // attention-grabbers landing on top of each other is worse than just letting the
            // star pill's persistent highlight (HUDView) do the reminding this time.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { announcePrestigeNudge() }
        }
    }

    /// A player can plausibly not know prestige exists the first time they're eligible, or
    /// forget it does once they've plateaued on a fully-built board again later - `engine.
    /// shouldNudgePrestige` (GameEngine.swift) covers both. The very first time, a toast
    /// alone wasn't reliably seen - it auto-dismisses in ~2s and the star pill's pulsing ring
    /// (HUDView) only helps if the player is looking right at that moment - so that one case
    /// gets a full sheet instead; every later nudge for the same moment still uses the toast.
    private func announcePrestigeNudge() {
        if engine.state.prestigeCount == 0 {
            if engine.hasSeenIntro(IntroKey.prestige) {
                showToast("You've earned enough to prestige! Tap the star for a permanent profit boost.")
            } else {
                present(.prestigeIntro)
            }
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
            sound.play(.denied)
            showToast("Coffee Break ready in \(Format.clock(engine.boostCooldownRemaining))")
            return
        }
        Haptics.success()
        sound.play(.reward)
        showToast("Coffee Break! ×\(Format.trim(ActivePlay.freeBoostMultiplier)) for \(Int(ActivePlay.freeBoostHours * 60)) minutes")
    }

    private func startRush() {
        if engine.rushActive {
            showToast("Rush Hour already running")
        } else if engine.startRush() {
            Haptics.success()
            sound.play(.reward)
            showToast("Rush Hour! ×\(Format.trim(ActivePlay.rushMultiplier)) for \(Format.duration(engine.state.rushDuration))")
        } else if engine.spendGems(ActivePlay.rushGemCost) {
            engine.startRush(force: true)
            Haptics.success()
            sound.play(.reward)
            showToast("Rush Hour started early")
        } else {
            sound.play(.denied)
            showToast("Ready in \(Format.clock(engine.rushCooldownRemaining)) · or \(ActivePlay.rushGemCost) gems")
        }
    }

    private func announce(_ drop: Recipes.Drop) {
        switch drop {
        case .none: return
        case .newCard(let venue, let station):
            sound.play(.reward)
            showToast("Recipe found: \(Balance.venue(venue).stations[station].name)")
        case .upgraded(let venue, let station, let stars):
            sound.play(.reward)
            showToast("\(Balance.venue(venue).stations[station].name) recipe → \(stars)★")
        case .duplicateGems(let gems):
            sound.play(.reward)
            showToast("Duplicate recipe → +\(gems) gems")
        }
        engine.objectWillChange.send()
    }

    /// A flat 2.2s worked for short confirmations ("Rush Hour already running") but a
    /// landmark crossing or the tutorial graduation line runs 3-4x longer and was gone
    /// before it could be read. Duration now scales with word count instead of every long
    /// message needing its own call site to remember a longer number.
    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        let wordCount = message.split(separator: " ").count
        let seconds = min(5.0, max(2.2, 1.2 + Double(wordCount) * 0.35))
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { toast = nil }
        }
    }
}

// MARK: - Bottom bar

/// The five main-nav buttons. Horizontal along the bottom in portrait; on iPad landscape
/// (see `RootView.landscapeContent`) the same buttons run down a leading sidebar instead -
/// `AnyLayout` swaps the container without duplicating a single button's logic or badges.
private struct BottomBar: View {
    @EnvironmentObject private var engine: GameEngine

    var axis: Axis = .horizontal
    let onVenues: () -> Void
    let onCollection: () -> Void
    let onQuests: () -> Void
    let onEvents: () -> Void
    let onShop: () -> Void

    private var layout: AnyLayout {
        axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 10))
    }

    var body: some View {
        layout {
            barButton("Venues", "map.fill",
                      badge: engine.nextLockedVenue.map { engine.canUnlock($0) } == true,
                      action: onVenues)
                .pulsingHighlight(engine.shouldNudgeSecondVenue, cornerRadius: 14)
            barButton("Staff", "person.2.fill",
                      badge: !engine.state.unassignedManagers.isEmpty || !engine.claimableErrands.isEmpty,
                      action: onCollection)
            barButton("Goals", "checklist",
                      badge: engine.claimableQuests > 0 || !engine.claimableAchievements.isEmpty,
                      target: .goalsTab, action: onQuests)
            barButton("Events", "calendar",
                      badge: eventsBadge, action: onEvents)
            barButton("Shop", "cart.fill", badge: engine.state.flashSale != nil, action: onShop)
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
