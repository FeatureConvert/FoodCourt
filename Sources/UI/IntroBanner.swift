import SwiftUI

/// A small dismissible explainer card, shown exactly once per `key` - the first time a screen
/// that carries one is opened. Persisted via `GameState.seenIntros` (`IntroKey` constants), so
/// once a player dismisses it, it never reappears, even across launches. Deliberately lighter
/// weight than `PerkChoiceView`'s primer or the full-screen prestige/legacy/welcome alerts:
/// this is for systems that are simply visible and unexplained the first time a tab is opened,
/// not a moment worth interrupting the player for.
struct IntroBanner: View {
    @EnvironmentObject private var engine: GameEngine
    let key: String
    let symbol: String
    let title: String
    let detail: String
    /// Pacing gate: banners can wait for the moment their system becomes relevant instead
    /// of firing on first sight of a tab (see the gate properties on GameEngine).
    var gate: Bool = true

    var body: some View {
        if gate, !engine.hasSeenIntro(key) {
            HStack(alignment: .top, spacing: 10) {
                GlyphIcon(symbol, tint: Theme.coin)
                    .frame(width: 20, height: 20)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.ink.opacity(0.5)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.body(13, weight: .black))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(Theme.body(11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { engine.markIntroSeen(key) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.ink.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .panel(Theme.panelRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.coin.opacity(0.5), lineWidth: 1.5)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
