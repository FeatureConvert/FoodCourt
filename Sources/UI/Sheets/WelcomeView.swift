import SwiftUI

/// Shown once, before the step-by-step tutorial coach cards begin. The coach cards teach the
/// controls by having the player use them; they never state the point of any of it or how to
/// play efficiently once managers take over - this fills that gap in one screen instead of
/// scattering "how to play" text across the game.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    private let tips: [(symbol: String, text: String)] = [
        ("arrow.triangle.2.circlepath", "Keep coins moving - buy the next level the moment you can afford it."),
        ("person.fill.checkmark", "A staffed station runs itself, even while the app is closed. Hire as soon as you can."),
        ("bolt.fill", "Milestone levels (40, 100, 250…) double your speed or profit outright - worth rushing toward."),
        ("building.2.fill", "A new venue almost always beats another level in the old one - unlock it as soon as it's affordable."),
        ("star.fill", "Franchising resets the board but keeps a permanent profit bonus. Do it once you've built out everything you can."),
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
                    Text("Build a food-court empire: automate every station across five venues, then franchise out for a permanent edge that carries into the next run.")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

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
