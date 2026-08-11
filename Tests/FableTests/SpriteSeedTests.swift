import XCTest
import SwiftUI
@testable import Fable

/// Guards the seed-compatibility contract of the character art rebuild, and renders a contact
/// sheet for eyeballing the figures - sprite geometry is `accessibilityHidden` Canvas drawing
/// with no assertable output, so the real acceptance test is looking at it.
final class SpriteSeedTests: XCTestCase {

    /// The wardrobe draws are slots 1-4 of a stateful xorshift. The rebuild widened slots 5-7
    /// and appended 8-12, which is only safe because `next(3)` and `next(5)` each consume
    /// exactly one step - so the four colour draws in front of them must be untouched.
    ///
    /// This table was generated independently of the Swift implementation (from the xorshift
    /// definition directly) so that it actually checks the code rather than agreeing with it.
    func testWardrobeSlotsAreUnchangedByTheRebuild() {
        let golden: [(Int, String, String, String, String)] = [
            (1, "#F2C49B", "#B8B2AD", "#57A773", "#37405C"),
            (2, "#5C3A24", "#5B3A20", "#E08A50", "#2E3A2F"),
            (3, "#5C3A24", "#3C4A6B", "#8367C7", "#37405C"),
            (4, "#A9714B", "#2E2A2B", "#57A773", "#2E3A2F"),
            (5, "#5C3A24", "#B8B2AD", "#D4685A", "#5C4632"),
            (7, "#F7D9BE", "#3C4A6B", "#8367C7", "#5C4632"),
            (42, "#7A4E33", "#5B3A20", "#D4685A", "#2E3A2F"),
            (101, "#F2C49B", "#C8873B", "#4C79C0", "#4A3A52"),
            (1000, "#5C3A24", "#2E2A2B", "#E08A50", "#4A3A52"),
            (31337, "#A9714B", "#8E4A3C", "#8367C7", "#2E3A2F"),
        ]

        for (seed, skin, hair, shirt, pants) in golden {
            let w = CustomerSprite.wardrobeForTesting(seed: seed)
            XCTAssertEqual(w.skin, skin, "skin drifted for seed \(seed)")
            XCTAssertEqual(w.hair, hair, "hair drifted for seed \(seed)")
            XCTAssertEqual(w.shirt, shirt, "shirt drifted for seed \(seed)")
            XCTAssertEqual(w.pants, pants, "pants drifted for seed \(seed)")
        }
    }

    /// The queue seeds figures with `seed + i`, so adjacent seeds must not look related.
    func testAdjacentSeedsProduceDifferentPeople() {
        let looks = (1...12).map { CustomerSprite.wardrobeForTesting(seed: $0) }
        let distinct = Set(looks.map { "\($0.skin)\($0.hair)\($0.shirt)\($0.pants)" })
        XCTAssertGreaterThan(distinct.count, 9,
                             "twelve consecutive seeds collapsed to \(distinct.count) looks")
    }

    /// Not an assertion - writes a PNG contact sheet to the simulator's tmp and prints the
    /// path, so the figures can actually be reviewed against design's reference.
    @MainActor
    func testRenderContactSheet() throws {
        let sheet = VStack(alignment: .leading, spacing: 18) {
            label("Queue seeds 1-8, drawn at 2x queue size")
            row((1...8).map { seed in
                AnyView(CustomerSprite(seed: seed).equatable().frame(width: 88, height: 124))
            })

            label("Seeds 9-16")
            row((9...16).map { seed in
                AnyView(CustomerSprite(seed: seed).equatable().frame(width: 88, height: 124))
            })

            label("Variants: customer / staff / golden / critic")
            row([SpriteVariant.customer, .staff, .golden, .critic].map { v in
                AnyView(CustomerSprite(seed: 7, variant: v).equatable()
                    .frame(width: 120, height: 168))
            })

            label("Hats + spiky hair: seeds 22, 34, 53, 86 (paper) / 15, 16 (beanie) / 2, 5 (spiky)")
            row([22, 34, 53, 86, 15, 16, 2, 5].map { seed in
                AnyView(CustomerSprite(seed: seed).equatable().frame(width: 100, height: 140))
            })

            label("Rarity frames: common / rare / epic / legendary")
            row(ManagerRarity.allCases.map { r in
                AnyView(ZStack {
                    ManagerRarityFrame(rarity: r)
                    CustomerSprite(seed: 42).equatable()
                        .frame(width: 52, height: 73).offset(y: 5)
                }
                .frame(width: 90, height: 90))
            })

            label("Actual queue size, 44x62")
            row((1...6).map { seed in
                AnyView(CustomerSprite(seed: seed).equatable().frame(width: 44, height: 62))
            })
        }
        .padding(24)
        .background(Theme.ink)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            return XCTFail("ImageRenderer produced nothing")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sprite-contact-sheet.png")
        try data.write(to: url)
        print("CONTACT_SHEET_PATH=\(url.path)")
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textDim)
    }

    private func row(_ views: [AnyView]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(views.enumerated()), id: \.offset) { $0.element }
        }
    }
}
