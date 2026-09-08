import XCTest
import SwiftUI
@testable import Fable

/// Measures what the venue stage's animated layers actually cost per frame.
///
/// `StageAtmosphere` is documented as costing about nothing next to the figures standing in
/// front of it. That was an argument, not a measurement, and it is the kind of claim that
/// deserves one: the layer redraws 30 times a second on the game's primary screen, in a genre
/// where people leave the app open for hours. This pins the number so the claim can be checked
/// rather than believed - and so a future change that makes the layer ten times more expensive
/// shows up here instead of in a battery complaint.
///
/// Absolute timings from `ImageRenderer` are not device frame times; the harness itself costs
/// more than the drawing. So every case measures against an empty `Canvas` of the same size and
/// reports the difference, which is the part attributable to the drawing code.
@MainActor
final class StageAtmospherePerfTests: XCTestCase {

    /// The portrait stage's real geometry - `VenueStageView` is pinned to `fixedHeight: 168`,
    /// and 374pt is the width it measured at on an iPhone 17 Pro.
    private let stageSize = CGSize(width: 374, height: 168)
    private let iterations = 40

    // MARK: measurement

    private func renderCost(_ view: some View, size: CGSize) -> TimeInterval {
        let sized = view.frame(width: size.width, height: size.height)
        // One warm-up render so first-call setup does not land in the timed loop.
        _ = ImageRenderer(content: sized).cgImage

        let start = Date()
        for _ in 0..<iterations {
            let renderer = ImageRenderer(content: sized)
            renderer.scale = 1
            _ = renderer.cgImage
        }
        return Date().timeIntervalSince(start) / Double(iterations)
    }

    private func baselineCost(size: CGSize) -> TimeInterval {
        renderCost(Canvas { _, _ in }, size: size)
    }

    // MARK: the claim

    /// The documented claim, made checkable: the atmosphere layer costs less per frame than the
    /// six figures standing in front of it.
    ///
    /// Deliberately a ratio and not a millisecond threshold - absolute numbers depend on the
    /// machine running CI, but the relationship between two views rendered through the same
    /// harness on the same machine does not.
    func testAtmosphereCostsLessThanTheQueueItSitsBehind() {
        let baseline = baselineCost(size: stageSize)

        let atmosphere = renderCost(StageAtmosphere(accent: Theme.coin), size: stageSize) - baseline

        let queue = HStack(alignment: .bottom, spacing: 6) {
            ForEach(1...6, id: \.self) { seed in
                CustomerSprite(seed: seed).equatable().frame(width: 44, height: 62)
            }
        }
        let queueCost = renderCost(queue, size: stageSize) - baseline

        print(String(format: "PERF baseline=%.3fms atmosphere=%.3fms queue(6)=%.3fms ratio=%.2f",
                     baseline * 1000, atmosphere * 1000, queueCost * 1000,
                     queueCost > 0 ? atmosphere / queueCost : .nan))

        XCTAssertLessThan(atmosphere, queueCost,
                          "StageAtmosphere now costs more per frame than the six customers it "
                          + "sits behind - its doc comment claims the opposite. Either trim the "
                          + "particle counts or correct the comment.")
    }

    /// A blink is meant to be nearly free, because it redraws four paths over a cached figure
    /// rather than re-rendering the ~40-path figure itself. If someone folds the blink into
    /// `CustomerSprite` this ratio collapses.
    func testBlinkOverlayIsCheaperThanTheFigureItCoversFor() {
        let spriteSize = CGSize(width: 44, height: 62)
        let baseline = baselineCost(size: spriteSize)

        let sprite = renderCost(CustomerSprite(seed: 1).equatable(), size: spriteSize) - baseline
        let overlay = renderCost(
            BlinkOverlay(look: SpriteBlinkLook(seed: 1, variant: .customer), phase: 2),
            size: spriteSize) - baseline

        print(String(format: "PERF sprite=%.3fms blinkOverlay=%.3fms ratio=%.2f",
                     sprite * 1000, overlay * 1000, sprite > 0 ? overlay / sprite : .nan))

        XCTAssertLessThan(overlay, sprite,
                          "the eyelid layer costs more than redrawing the whole figure, which "
                          + "defeats the reason it is a separate overlay at all")
    }

    // Reduce-motion has no benchmark here on purpose: `accessibilityReduceMotion` is a
    // read-only environment key, so it cannot be injected, and reshaping `StageAtmosphere` to
    // take an injectable flag would be distorting the production API to suit a test. The guard
    // is `if !reduceMotion { ... }` with no else branch - inspection covers it.
}
