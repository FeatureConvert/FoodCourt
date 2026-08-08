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
            symbol: "star.fill", title: "Franchising and research",
            text: """
            Once you have earned enough, franchising resets the board in exchange for \
            Franchise Stars. Every star is +2% profit forever. Stars are also the currency \
            for the research tree. Staff, recipes and research all survive a reset — only \
            the board itself starts over.
            """),
        GuideSection(
            symbol: "calendar", title: "Events",
            text: """
            The daily calendar runs on a seven-day streak; miss a day and it restarts. The \
            festival is a weekly season with a 30-tier reward track, earned with tickets from \
            playing. The league puts you on a weekly ladder — finish in the top seven to go up.
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
                Not yet. Progress is stored on this device only, so deleting the app loses \
                it. Cloud sync is planned.
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
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.coin)
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
