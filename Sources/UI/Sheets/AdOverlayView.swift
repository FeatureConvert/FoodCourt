import SwiftUI

/// A stand-in for a rewarded-ad unit. Deliberately looks like an ad rather than pretending
/// to be one - the point is to exercise the reward flow end to end.
struct AdOverlayView: View {
    @EnvironmentObject private var ads: AdService

    @State private var wobble = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 18) {
                Text("SPONSORED")
                    .font(Theme.body(11, weight: .black))
                    .foregroundStyle(Theme.textDim)
                    .tracking(2)

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.gemDeep, Theme.panelRaised],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 12) {
                        CoinIcon()
                            .frame(width: 70, height: 70)
                            .rotationEffect(.degrees(wobble ? 12 : -12))
                            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: wobble)
                        Text("Placeholder Ad Unit")
                            .font(Theme.title(20))
                            .foregroundStyle(Theme.text)
                        Text("Swap AdService.play() for your ad SDK")
                            .font(Theme.body(11, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .frame(height: 260)
                .padding(.horizontal, 28)

                Text("Reward in \(ads.secondsRemaining)s")
                    .font(Theme.numeric(16))
                    .foregroundStyle(Theme.text)

                Button {
                    ads.skip()
                } label: {
                    Text("Skip")
                        .font(Theme.body(13, weight: .bold))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.panelRaised, shadow: Theme.ink, radius: 12))
            }
        }
        .onAppear { wobble = true }
    }
}
