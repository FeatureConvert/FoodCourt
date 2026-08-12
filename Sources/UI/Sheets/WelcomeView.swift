import SwiftUI

/// Shown once, before the step-by-step tutorial coach cards begin. The coach cards teach the
/// controls by having the player use them; they never state the point of any of it or how to
/// play efficiently once managers take over - this fills that gap in one screen instead of
/// scattering "how to play" text across the game.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    /// The whole arc in three beats. A real playtest showed the old tip list taught
    /// efficiency without ever saying what the game IS - a non-idle-gamer finished the
    /// tutorial with no idea of the end goal. Worse, the final tip said to franchise "once
    /// you've built out everything you can," which is exactly the stalling the staleness
    /// tax punishes. This screen now answers "what's the point?" first; the Next Goal chip
    /// on the HUD carries it from there, one step at a time.
    private let journey: [(number: String, symbol: String, title: String, text: String)] = [
        ("1", "takeoutbag.and.cup.and.straw.fill", "Serve and staff",
         "Earn coins, buy levels, and hire managers so stations run themselves - even while the app is closed."),
        ("2", "building.2.fill", "Open every venue",
         "From Burger Shack to the Midnight Diner and the Food Truck Rally - each venue multiplies what a run can earn, and the later ones bend the rules."),
        ("3", "star.fill", "Franchise, forever",
         "Reset the board for Stars: a permanent profit bonus plus research that never resets. Every run starts bigger. Maxing that empire is the game."),
    ]

    private let tips: [(symbol: String, text: String)] = [
        ("arrow.triangle.2.circlepath", "Keep coins moving - buy the next level the moment you can afford it."),
        ("bolt.fill", "Milestone levels (40, 100, 250…) double your speed or profit outright - worth rushing toward."),
        ("gift.fill", "Some milestone levels also offer a permanent perk to pick - save them for stations you're actually committed to."),
        ("star.fill", "Don't sit on a finished board: costs creep up the longer you wait, so franchising every few days beats holding out."),
    ]

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 10) {
                    StarIcon().frame(width: 56, height: 56)
                    Text("Welcome to Food Court Tycoon")
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                SectionLabel(text: "The journey")

                VStack(spacing: 10) {
                    ForEach(journey, id: \.number) { phase in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle().fill(Theme.coin)
                                Text(phase.number)
                                    .font(Theme.numeric(13))
                                    .foregroundStyle(Theme.ink)
                            }
                            .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phase.title)
                                    .font(Theme.body(13, weight: .black))
                                    .foregroundStyle(Theme.text)
                                Text(phase.text)
                                    .font(Theme.body(11, weight: .medium))
                                    .foregroundStyle(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .panel(Theme.panel)

                SectionLabel(text: "To play efficiently")

                VStack(spacing: 8) {
                    ForEach(tips, id: \.text) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: tip.symbol)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.coin)
                                .frame(width: 20)
                            Text(tip.text)
                                .font(Theme.body(12, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(12)
                .panel(Theme.panel)

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Text("Let's cook")
                        .font(Theme.body(16, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.coin, shadow: Theme.coinDeep))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
    }
}
