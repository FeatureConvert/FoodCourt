import SwiftUI

/// A coach card pinned above the bottom bar. It never blocks the screen — the player can
/// still touch anything — because each step is completed by doing the thing, not by tapping
/// "Next" on a modal.
struct TutorialOverlay: View {
    @EnvironmentObject private var engine: GameEngine
    let onSkip: () -> Void

    var body: some View {
        if let step = engine.state.tutorial.current {
            VStack(spacing: 0) {
                Spacer()
                card(step)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 96)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(true)
        }
    }

    private func card(_ step: TutorialStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Theme.coin)
                Text("\(step.rawValue + 1)")
                    .font(Theme.numeric(15))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(step.title)
                        .font(Theme.body(14, weight: .black))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(engine.state.tutorial.progressLabel)
                        .font(Theme.body(10, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                }
                Text(step.detail)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onSkip) {
                    Text("Skip tutorial")
                        .font(Theme.body(11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .panel(Theme.panelRaised, radius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.coin.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
    }
}

/// Pulses a ring around whichever control the current tutorial step is asking for.
///
/// The target is optional so a call site can opt out entirely — the tutorial only ever
/// points at the first station, and passing a different target for the rest lit up every
/// station's controls at once.
struct TutorialHighlight: ViewModifier {
    @EnvironmentObject private var engine: GameEngine
    let target: TutorialTarget?

    private var isActive: Bool {
        guard let target else { return false }
        return engine.state.tutorial.current?.target == target
    }

    func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = 0.5 + 0.5 * sin(t * 4)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.coin, lineWidth: 2 + 1.5 * pulse)
                        .opacity(0.55 + 0.45 * pulse)
                        .padding(-4)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func tutorialHighlight(_ target: TutorialTarget?) -> some View {
        modifier(TutorialHighlight(target: target))
    }
}
