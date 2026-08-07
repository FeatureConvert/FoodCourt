import SwiftUI

/// The game has no ads at all - no banners, no interstitials, no rewarded videos. That is a
/// deliberate product decision, so it is stated plainly where a player is most likely to be
/// bracing for the opposite: the shop, and the settings screen.
struct AdFreeBadge: View {
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.positive.opacity(0.18))
                Image(systemName: "hand.raised.slash.fill")
                    .font(.system(size: compact ? 14 : 17, weight: .black))
                    .foregroundStyle(Theme.positive)
            }
            .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("No ads. Ever.")
                    .font(Theme.body(compact ? 13 : 14, weight: .black))
                    .foregroundStyle(Theme.text)
                if !compact {
                    Text("No banners, no video, nothing to sit through. Every boost in the game is free.")
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .panel(Theme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.positive.opacity(0.45), lineWidth: 1.5)
        )
    }
}
