import SwiftUI

/// A hard-to-miss one-time alert for a genuinely big, easy-to-miss moment - reaching the
/// first Franchise (prestige) or first Legacy reset. Neither is a small toast could reliably
/// carry: `RootView`'s toast auto-dismisses in ~2s, and the star pill's pulsing ring
/// (`HUDView`) only helps if the player happens to be looking at the HUD right when the
/// threshold clears. A full sheet the first time only guarantees they actually see it; every
/// later nudge for the same moment falls back to the lighter toast, so it isn't intrusive
/// on repeat.
struct BigMomentAlertView: View {
    let symbol: String
    let headline: String
    let detail: String
    let stat: (label: String, value: String)
    let ctaTitle: String
    let onCTA: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Theme.star.opacity(0.18)).frame(width: 96, height: 96)
                    GlyphIcon(symbol, tint: Theme.star).frame(width: 44, height: 44)
                }
                .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(headline)
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                }

                HStack {
                    Text(stat.label)
                        .font(Theme.body(12, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    Text(stat.value)
                        .font(Theme.numeric(18))
                        .foregroundStyle(Theme.star)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .panel(Theme.panel)

                Spacer(minLength: 0)

                Button {
                    dismiss()
                    onCTA()
                } label: {
                    Text(ctaTitle)
                        .font(Theme.body(16, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.star, shadow: Theme.coinDeep))

                Button { dismiss() } label: {
                    Text("Later")
                        .font(Theme.body(13, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
    }
}
