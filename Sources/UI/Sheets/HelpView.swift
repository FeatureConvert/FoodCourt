import SwiftUI

/// The in-game manual: a short guide to each system, then an FAQ. Written to answer the
/// questions a player actually asks, including the awkward ones about money.
struct HelpView: View {
    @EnvironmentObject private var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    let onToast: (String) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case guide, faq
        var id: String { rawValue }
        var title: String { self == .guide ? "Guide" : "FAQ" }
    }

    @State private var tab: Tab = .guide
    @State private var expanded: Set<String> = []

    var body: some View {
        SheetScaffold(title: "Help", subtitle: "How everything works") {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            switch tab {
            case .guide: guide
            case .faq: faq
            }
        }
    }

    // MARK: Guide

    private var guide: some View {
        Group {
            Button {
                engine.restartTutorial()
                onToast("Tutorial restarted")
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Replay the tutorial")
                            .font(Theme.body(14, weight: .black))
                            .foregroundStyle(Theme.ink)
                        Text("Five steps, about a minute")
                            .font(Theme.body(11, weight: .medium))
                            .foregroundStyle(Theme.ink.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .buttonStyle(ChunkyButtonStyle(fill: Theme.coin, shadow: Theme.coinDeep))

            ForEach(Self.guideSections, id: \.title) { section in
                section
            }
        }
    }

    private static let guideSections: [GuideSection] = [
        GuideSection(
            symbol: "hand.tap.fill", title: "The basics",
            text: """
            Tap a station to cook a batch. Each batch serves a customer and pays coins. \
            Spend those coins on levels — a higher level pays more per batch. Hire a manager \
            and the station runs on its own, including while the app is closed.
            """),
        GuideSection(
            symbol: "flame.fill", title: "Combo and Rush Hour",
            text: """
            Taps within a second and a half of each other build a combo, up to ×10, and it \
            multiplies everything you earn while it lasts — even from staffed stations, so \
            it is always worth tapping. Rush Hour is a 60-second ×5 on a 20-minute cooldown. \
            The coffee cup is a free ×2 for 15 minutes.
            """),
        GuideSection(
            symbol: "crown.fill", title: "Golden customers",
            text: """
            Now and then a VIP with a crown walks in and glows. Tap them within five seconds \
            and they tip you between 30 seconds and two minutes of income.
            """),
        GuideSection(
            symbol: "sparkles", title: "Milestones and perks",
            text: """
            Every station gets automatic bonuses at levels 10, 25, 50, 100, 200 and 400. At \
            25, 50 and 100 you also pick a perk: more profit, faster cycles, or a chance to \
            serve twice. Perks are permanent for that run and stack with the milestone.
            """),
        GuideSection(
            symbol: "person.2.fill", title: "Staff",
            text: """
            Managers are characters, not a switch. Each has a trait — some speed up the \
            station they run, some lift the whole venue, some improve offline earnings or \
            your tap value. Better staff come from goals, the festival, and the league. Move \
            them between stations from the Staff tab.
            """),
        GuideSection(
            symbol: "book.closed.fill", title: "Recipes",
            text: """
            Levelling a station can drop its recipe card. Duplicates add a star, worth more \
            profit on that station, and completing all six cards in a venue pays a permanent \
            +25% across that venue.
            """),
        GuideSection(
            symbol: "scope", title: "What's the goal?",
            text: """
            Build a food court that runs itself, open all five venues, then Franchise: \
            reset the board for Stars, a permanent profit bonus that makes every future \
            run bigger. Stars fund permanent research; five franchises unlock Legacy, an \
            even bigger reset. Maxing all of it is a months-long journey — the Next Goal \
            chip under the HUD always shows your single next step, and the Map tab in the \
            Franchise sheet shows the whole road.
            """),
        GuideSection(
            symbol: "star.fill", title: "Franchising and research",
            text: """
            Once you have earned enough, franchising resets the board in exchange for \
            Franchise Stars — a permanent profit bonus that grows with every star you've \
            ever earned. Don't sit on a finished board: costs creep up the longer a board \
            goes without a reset, so franchising every few days beats waiting for perfect. \
            Stars are also the currency for research, and each franchise funds your next \
            few ranks — research is a months-long project, not a single run's shopping \
            trip. Recipes and research survive a reset; coin-hired staff does not.
            """),
        GuideSection(
            symbol: "calendar", title: "Events",
            text: """
            The festival is a weekly season with a 30-tier reward track, earned with tickets \
            from playing. The league puts you on a weekly ladder — finish in the top seven to \
            go up.
            """),
        GuideSection(
            symbol: "trophy.fill", title: "Achievements",
            text: """
            The Goals tab has an Achievements page alongside Quests: one-time trophies for \
            lifetime earnings, customers served, taps, staff owned, legendary staff, venues \
            opened, league tier, and prestiges. Each pays gems once and stays claimed forever.
            """),
        GuideSection(
            symbol: "flame.circle.fill", title: "Login streak",
            text: """
            Claiming a daily reward on consecutive days builds a streak on top of the 7-day \
            cycle — it never resets to day 1, and milestone chests keep coming all the way \
            to day 300. A Streak Freeze, bought with gems, forgives exactly one missed day.
            """),
        GuideSection(
            symbol: "map.fill", title: "Roadmap",
            text: """
            The Franchise sheet has a Map tab: one list of everything you're working toward — \
            venues, league tiers, research branches, prestige count, and Legacy level — with \
            what's already done checked off.
            """),
        GuideSection(
            symbol: "person.3.fill", title: "Crews",
            text: """
            Certain managers have chemistry: staff every member of a named crew anywhere \
            in the same venue and that whole venue earns a bonus. The crew board on the \
            Staff tab shows every combination and who's still missing.
            """),
        GuideSection(
            symbol: "trophy.fill", title: "Face-Offs",
            text: """
            Send your three best benched managers to out-cook a rival crew, from the \
            Errands page. Rarity and long service set your win odds — shown before you \
            commit — and higher stakes pay better, up to a chance at an Epic recruit. \
            Losses still pay a little; the time was real either way.
            """),
        GuideSection(
            symbol: "takeoutbag.and.cup.and.straw.fill", title: "Catering",
            text: """
            Once a day a big order arrives in Goals naming specific stations — those \
            counters have to actually run to fill it before it expires. Delivery pays \
            gems, coins, and festival tickets; a fresh order arrives daily either way.
            """),
        GuideSection(
            symbol: "crown.fill", title: "Signature Dish",
            text: """
            Fully 3-star a venue's recipe set and you can crown one of its stations the \
            Signature Dish for ×1.5 profit there. Re-crown a different station anytime, \
            free — it's a standing choice, not a one-shot.
            """),
        GuideSection(
            symbol: "briefcase.fill", title: "Manager errands",
            text: """
            Send an idle manager on an errand from the Staff tab's Errands page for 2, 6 or \
            12 hours. They come back with gems and coins — roughly half what they'd have \
            earned staffing a station, so it's a real tradeoff, not free money.
            """),
        GuideSection(
            symbol: "bell.badge.fill", title: "Customer orders",
            text: """
            Sometimes a specific staffed station gets a pulsing "ORDER UP" ring. Serve it \
            before the ring times out for a coin bonus. Miss it and nothing is lost — it just \
            clears.
            """),
        GuideSection(
            symbol: "paintbrush.fill", title: "Venue looks",
            text: """
            Tap a venue's hanging sign to open its look. A Neon reskin is available for coins \
            — purely visual, it never touches profit.
            """),
        GuideSection(
            symbol: "doc.text.fill", title: "Franchise Contracts",
            text: """
            After every Franchise you pick a Contract for the new run: each one trades a \
            strength for a weakness — faster cycles for lower profit, bigger payouts for \
            an earlier staleness tax. Play It Straight is always offered for a vanilla \
            run, and a contract only ever lasts until your next reset.
            """),
        GuideSection(
            symbol: "infinity", title: "Legacy",
            text: """
            After your fifth franchise, a Legacy option appears on the Franchise tab. It \
            resets stars, research, and your whole earnings history — the things an \
            ordinary franchise reset keeps — for a permanent +20% multiplier per level \
            PLUS one pick from the Legacy tree: permanent perks like starting capital, a \
            later staleness tax, or richer Franchise awards. Picks stack across Legacies \
            and never reset, so two empires at the same level can be built very differently.
            """),
        GuideSection(
            symbol: "star.circle.fill", title: "Guest Chef",
            text: """
            A rotating Legendary-tier manager is available each week from the Staff tab, \
            priced in gems. The pick changes every week and is exclusive to that purchase — \
            you won't find it from any other reward.
            """),
        GuideSection(
            symbol: "bell.fill", title: "Reminders",
            text: """
            Turn on Reminders in Settings for a nudge when Rush Hour is ready, offline \
            earnings are capped, or a festival or league deadline is close — only while the \
            app is closed.
            """),
        GuideSection(
            symbol: "gamecontroller.fill", title: "Game Center",
            text: """
            If Game Center is signed in, a Global Leaderboard button appears on the League tab \
            for lifetime earnings — separate from the simulated league table, which stays \
            exactly as private as before.
            """),
    ]

    // MARK: FAQ

    private var faq: some View {
        ForEach(Self.faqItems, id: \.question) { item in
            faqRow(item)
        }
    }

    private func faqRow(_ item: FAQItem) -> some View {
        let isOpen = expanded.contains(item.question)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if isOpen { expanded.remove(item.question) } else { expanded.insert(item.question) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(item.question)
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.textDim)
                }
                if isOpen {
                    Text(item.answer)
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Theme.panel, shadow: Theme.ink))
    }

    private static let faqItems: [FAQItem] = [
        FAQItem(question: "Are there ads?",
                answer: """
                No. None at all — no banners, no interstitials, no rewarded video. Every \
                boost in the game is given to you free on a cooldown.
                """),
        FAQItem(question: "Do I have to spend money to finish?",
                answer: """
                No. Nothing in the shop is required, and nothing is locked behind it. \
                Purchases speed things up and add a premium reward lane to the festival; \
                they do not gate any content.
                """),
        FAQItem(question: "What is the difference between the Carnival Pass and VIP?",
                answer: """
                The Carnival Pass unlocks the premium reward on all 30 tiers for the current \
                season only. VIP includes that pass every season, plus +25% profit forever \
                and a longer offline window. If you expect to play for more than a few \
                seasons, VIP is the cheaper route.
                """),
        FAQItem(question: "Does the game keep earning while it's closed?",
                answer: """
                Staffed stations do, at half rate, up to your offline cap — two hours by \
                default, more with Night Shift research or VIP. Stations without a manager \
                stop when you leave.
                """),
        FAQItem(question: "Why did my station's ring go solid and start glowing?",
                answer: """
                Because it is running faster than about three batches a second. Past that a \
                sweeping progress ring just looks like a flicker, so it switches to a steady \
                glow to show the station is running flat out.
                """),
        FAQItem(question: "What do I lose when I franchise?",
                answer: """
                Coins, station levels, perks, and every venue except the first. You keep your \
                staff, your recipe cards, your research, your gems, and every Franchise Star \
                you have ever earned — including the permanent profit bonus they carry.
                """),
        FAQItem(question: "Who am I competing against in the league?",
                answer: """
                Simulated rivals, not other players. The ladder is a solo challenge whose \
                pace is set by your own income, so it stays competitive as you grow. There \
                is no online play and the game never sends your data anywhere.
                """),
        FAQItem(question: "Can I move my save to another device?",
                answer: """
                Yes, if you're signed into iCloud. Settings shows your sync status, and Sync \
                Now pushes the current save immediately. Without iCloud signed in, progress \
                stays on this device only.
                """),
        FAQItem(question: "What's the difference between franchising and Legacy?",
                answer: """
                Franchising resets the board — coins, station levels, and every venue but the \
                first — while keeping stars, recipes and research (coin-hired staff is let \
                go). Legacy is separate and far rarer, unlocking after your fifth franchise, \
                and resets stars, research, and your entire earnings history too, in exchange \
                for a permanent +20% per level stacked on top of the star bonus. Think of it \
                as a second, much bigger reset for once the first one has run its course.
                """),
        FAQItem(question: "What are all these currencies?",
                answer: """
                Coins run the board - stations, levels, hires - and reset every franchise. \
                Gems are the premium currency from goals, events, and the shop; they buy \
                convenience, never required power. Stars come from franchising: every star \
                ever earned raises your permanent profit bonus, and your spendable balance \
                buys research. Purchased research stars (Star Infusion, Research Grant) are \
                spendable only — they fund research but never raise the permanent bonus, \
                which only real franchising can grow.
                """),
        FAQItem(question: "Do achievements, the streak, or any of the newer systems require spending money?",
                answer: """
                No — achievements, the login streak, errands, customer orders, the Roadmap, \
                Reminders, and the Global Leaderboard are all entirely free. Optional \
                purchases exist — gem sinks like the Streak Freeze and Guest Chef, and \
                real-money items like the Research Grant, which pays spendable research \
                stars scaled to your latest franchise — but nothing is gated behind any of \
                them, and every part of the game can be finished without spending.
                """),
        FAQItem(question: "I bought something and didn't get it.",
                answer: """
                Open Settings and tap Restore Purchases. Permanent purchases like VIP and \
                the Starter Pack will come back. Gems and the Carnival Pass are consumables \
                and are not restorable, so contact support if one is missing.
                """),
    ]
}

private struct GuideSection: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GlyphIcon(symbol, tint: Theme.coin)
                .frame(width: 19, height: 19)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.ink.opacity(0.5)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.body(14, weight: .black))
                    .foregroundStyle(Theme.text)
                Text(text)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .panel(Theme.panel)
    }
}

private struct FAQItem {
    let question: String
    let answer: String
}
