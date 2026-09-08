import XCTest
import SwiftUI
@testable import Fable

/// Guards two hand-maintained sets in `VenueSceneView` that nothing else can catch drifting.
///
/// Both are plain `Set<VenueTheme>` literals kept in sync with a `switch (theme, layer)` that
/// ends in `default: break`. Because that switch is not exhaustive, the compiler will not say a
/// word when a new theme is added - it just falls through and draws nothing. These are pure
/// membership checks with no rendering, so they cost nothing and run anywhere.
final class VenueSceneCoverageTests: XCTestCase {

    /// Every theme must draw a real room.
    ///
    /// `VenueStageView` routes anything outside `rebuilt` to the old `VenuePropsView`, which is
    /// the safety net that stops an unbuilt theme shipping as an empty room. That net currently
    /// catches nothing, and should stay that way: if this fails, someone added a `VenueTheme`
    /// without building its scene, and the game is quietly showing that venue the fallback art.
    func testEveryVenueThemeHasARebuiltScene() {
        let missing = Set(VenueTheme.allCases).subtracting(VenueSceneView.rebuilt)
        XCTAssertTrue(missing.isEmpty, """
            these themes have no rebuilt scene and are falling back to VenuePropsView: \
            \(missing.map(\.rawValue).sorted().joined(separator: ", ")).
            Add their (theme, .wall) / (theme, .floor) cases to VenueSceneView, or accept the \
            fallback deliberately and update this test.
            """)
    }

    /// `hasHangingLayer` must not claim a theme that draws nothing there.
    ///
    /// `VenueStageView` mounts `SwayingHangingLayer` - a 30fps `TimelineView` - for exactly the
    /// themes in this set. Listing one whose `(theme, .hangingLayer)` case does not exist buys a
    /// permanent timer on the game's always-visible screen to rotate an empty canvas, which is
    /// the specific cost the set was introduced to avoid.
    ///
    /// The converse matters too and is the harder one to notice: a theme that *does* draw a
    /// hanging layer but is left out of the set has its décor silently never mounted. Nobody
    /// sees a crash, the room just quietly loses its garland.
    ///
    /// This asserts against a list transcribed from the switch by hand, which is admittedly a
    /// second copy - but it is a copy in a file whose whole job is to fail when they disagree,
    /// rather than a third silent one.
    func testHangingLayerSetMatchesTheThemesThatDrawOne() {
        // Transcribed from the `case (…, .hangingLayer)` arms in VenueScenes.swift.
        let drawsHangingDecor: Set<VenueTheme> = [.burger, .diner, .pizza, .sushi, .taco, .dessert]

        XCTAssertEqual(VenueSceneView.hasHangingLayer, drawsHangingDecor, """
            hasHangingLayer and the (theme, .hangingLayer) switch arms have diverged.
            In the set but not drawing: \
            \(VenueSceneView.hasHangingLayer.subtracting(drawsHangingDecor).map(\.rawValue).sorted()) \
            - each of these runs a 30fps timeline to sway nothing.
            Drawing but not in the set: \
            \(drawsHangingDecor.subtracting(VenueSceneView.hasHangingLayer).map(\.rawValue).sorted()) \
            - each of these has décor that is never shown.
            """)
    }

    /// The food truck is the one room with no hanging décor, and that is deliberate rather than
    /// an omission - pinned here so nobody "fixes" it by adding it to the set and mounting a
    /// timeline over an empty canvas.
    func testFoodTruckDeliberatelyHasNoHangingLayer() {
        XCTAssertFalse(VenueSceneView.hasHangingLayer.contains(.foodtruck))
        XCTAssertTrue(VenueSceneView.rebuilt.contains(.foodtruck),
                      "the food truck still needs a rebuilt room even without hanging décor")
    }
}
