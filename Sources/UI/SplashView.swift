import SwiftUI

/// Bridges the system launch screen (icon + background only - Apple's own guidance is to
/// keep that static and text-free, since it can't be localized and has to render before any
/// app code runs) into the real UI. This is where the branding and loading feedback that a
/// launch screen can't provide actually belong: same background and mark, but now with the
/// wordmark and a loading bar for the async setup (StoreKit products, cloud reconcile,
/// Game Center) that's otherwise invisible while it runs.
struct SplashView: View {
    @State private var sweep = false

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

                VStack(spacing: 5) {
                    Text("FOOD COURT TYCOON")
                        .font(Theme.title(21))
                        .foregroundStyle(Theme.text)
                        .tracking(1.4)
                    Text("Build your empire, one order at a time")
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(.top, 20)

                Spacer()

                loadingBar
                    .padding(.bottom, 64)
            }
        }
        .onAppear { sweep = true }
        .transition(.opacity)
    }

    private var loadingBar: some View {
        GeometryReader { geo in
            let fill = geo.size.width * 0.36
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panel)
                Capsule()
                    .fill(
                        LinearGradient(colors: [Theme.coin.opacity(0), Theme.coin, Theme.coin.opacity(0)],
                                      startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: fill)
                    .offset(x: sweep ? geo.size.width : -fill)
                    .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false), value: sweep)
            }
        }
        .frame(width: 168, height: 6)
        .clipShape(Capsule())
    }
}
