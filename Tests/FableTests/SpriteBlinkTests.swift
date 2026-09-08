import XCTest
import SwiftUI
@testable import Fable

/// Guards the blink layer.
///
/// The thing that can actually break here is silent: `BlinkOverlay` positions an eyelid from
/// its own copy of the rig numbers (`SpriteFaceRig`), while `CustomerSprite` draws the eye from
/// literals inline in its `Canvas` closure. Nothing in the type system ties the two together,
/// so if the head ever moves, the lids stay behind and every customer blinks somewhere on their
/// cheek. There is no constant to compare against, so the test renders both layers and checks
/// the pixels - which is the only check that actually proves alignment rather than restating
/// the same numbers a third time.
@MainActor
final class SpriteBlinkTests: XCTestCase {

    // Render at exactly 2x the 100 x 150 design frame at scale 1, so a design coordinate maps
    // to a pixel by doubling it and nothing has to guess at a device scale.
    private let renderW: CGFloat = 200
    private let renderH: CGFloat = 300

    /// A seed whose face draws pupils rather than the arched squint that sits blinks out.
    /// Asserted rather than assumed - if the wardrobe roll ever shifts this seed onto face 2
    /// the pixel tests below would pass vacuously against an eyelid that never drew.
    private let blinkingSeed = 1

    // MARK: geometry

    func testChosenSeedActuallyBlinks() {
        XCTAssertTrue(SpriteBlinkLook(seed: blinkingSeed, variant: .customer).canBlink,
                      "seed \(blinkingSeed) rolled the arched-eye face; pick another for the pixel tests")
    }

    /// The alignment guard. Samples a patch of pupil - deliberately a region and not a single
    /// pixel, because a one-pixel probe beside a 1.7px catch-light is a coin flip against
    /// antialiasing rather than a test. Open, that patch is solid pupil ink; shut, the lid has
    /// replaced it with skin. If `SpriteFaceRig` ever drifts from the figure's own rig, the lid
    /// lands off the eye and the shut case stays dark.
    func testShutLidCoversThePupil() throws {
        let open = try bitmap(phase: 0)
        let shut = try bitmap(phase: 2)

        for side in [CGFloat(-1), CGFloat(1)] {
            let probe = pupilProbe(side: side)
            let before = open.darkFraction(in: probe)
            let after = shut.darkFraction(in: probe)

            XCTAssertGreaterThan(before, 0.85,
                                 "expected solid pupil ink at \(probe) before blinking, got \(before)")
            XCTAssertLessThan(after, 0.10,
                              "eyelid did not cover the pupil at \(probe) (still \(after) dark) - "
                              + "SpriteFaceRig has probably drifted from CustomerSprite's rig")
        }
    }

    /// The three quantised states have to be three genuinely different renders, or the middle
    /// step is buying nothing and the blink is a two-frame pop.
    ///
    /// Tested as pairwise distinctness rather than as an ordering, because mean brightness over
    /// the socket is deliberately *not* monotonic in how shut the eye is: the shut state adds
    /// the lash stroke back as ink, so it reads slightly darker than the mid state even though
    /// its lid has travelled further. Distinctness is the property that actually matters here.
    func testEachBlinkPhaseIsADistinctRender() throws {
        let socket = eyeSocket(side: -1)
        let means = try [0, 1, 2].map { try bitmap(phase: $0).meanLuminance(in: socket) }

        for (a, b) in [(0, 1), (1, 2), (0, 2)] {
            XCTAssertGreaterThan(
                abs(means[a] - means[b]), 0.03,
                "blink phases \(a) and \(b) rendered near-identically "
                + "(\(means[a]) vs \(means[b])) - the quantisation has collapsed")
        }

        // The one ordering that is safe to pin: any amount of lid is lighter than none, because
        // the open eye is the only state showing a full pupil.
        XCTAssertLessThan(means[0], means[1], "a mid-blink was not lighter than a wide-open eye")
        XCTAssertLessThan(means[0], means[2], "a shut eye was not lighter than a wide-open eye")
    }

    /// Glasses (accessory 1) and the critic's monocle draw rings of radius 4.8 and 5 around the
    /// eye. The lid is clipped to a 2.7 socket so it can never shave them; this samples a band
    /// out on the ring, where the lid must not reach.
    func testLidDoesNotReachTheGlassesRing() throws {
        let cx = 50 - SpriteFaceRig.eyeDX
        let ring = DesignRect(x0: cx - 1, x1: cx + 1,
                              y0: SpriteFaceRig.eyeCY - 4.6, y1: SpriteFaceRig.eyeCY - 3.4)

        let open = try bitmap(phase: 0).meanLuminance(in: ring)
        let shut = try bitmap(phase: 2).meanLuminance(in: ring)

        XCTAssertEqual(open, shut, accuracy: 0.02,
                       "the eyelid painted outside its socket - the clip in BlinkOverlay is gone")
    }

    // MARK: schedule

    func testPhaseIsDeterministic() {
        for seed in 1...20 {
            let t = 123.456
            XCTAssertEqual(SpriteBlink.phase(seed: seed, at: t),
                           SpriteBlink.phase(seed: seed, at: t))
        }
    }

    /// A blink is meant to be rare. If this ever climbs, every queued figure is redrawing its
    /// eyelid layer far more often than intended.
    func testEyesAreOpenAlmostAllTheTime() {
        for seed in [1, 7, 42, 101, 1000] {
            var closed = 0
            let samples = 6000
            for i in 0..<samples where SpriteBlink.phase(seed: seed, at: Double(i) / 30) > 0 {
                closed += 1
            }
            let duty = Double(closed) / Double(samples)
            XCTAssertGreaterThan(duty, 0.015, "seed \(seed) barely blinks (duty \(duty))")
            XCTAssertLessThan(duty, 0.09, "seed \(seed) blinks far too often (duty \(duty))")
        }
    }

    /// The point of keying the period and offset off the seed is that a queue never blinks in
    /// unison - synchronised blinking reads as a rendering tic, not as people.
    func testQueueDoesNotBlinkInUnison() {
        // The queue seeds consecutively, so these are the seeds that actually stand together.
        let queue = Array(1...6)
        var everSimultaneous = 0
        for i in 0..<3000 {
            let t = Double(i) / 30
            let blinking = queue.filter { SpriteBlink.phase(seed: $0, at: t) > 0 }.count
            if blinking > 2 { everSimultaneous += 1 }
        }
        XCTAssertLessThan(everSimultaneous, 30,
                          "more than two of six queued customers blinked together on "
                          + "\(everSimultaneous) frames - the per-seed offset is not spreading them")
    }

    /// Reduce-motion parks the figure with its eyes open. Nothing asserts this in the view
    /// layer, so it is worth pinning that the open state is genuinely a no-op render.
    func testOpenPhaseDrawsNothing() throws {
        let bare = try bitmap(phase: 0, includeOverlay: false)
        let open = try bitmap(phase: 0, includeOverlay: true)

        for side in [CGFloat(-1), CGFloat(1)] {
            let socket = DesignRect(x0: 50 + side * SpriteFaceRig.eyeDX - 3,
                                    x1: 50 + side * SpriteFaceRig.eyeDX + 3,
                                    y0: SpriteFaceRig.eyeCY - 3, y1: SpriteFaceRig.eyeCY + 3)
            XCTAssertEqual(bare.meanLuminance(in: socket), open.meanLuminance(in: socket),
                           accuracy: 0.001,
                           "an open-phase overlay changed the figure inside the eye socket")
        }
    }

    // MARK: contact sheet

    /// Not an assertion - the same escape hatch `SpriteSeedTests` uses. Writes a PNG showing
    /// each phase across a spread of faces so the blink can be eyeballed, including the seeds
    /// that wear glasses and the critic that wears a monocle.
    func testRenderBlinkContactSheet() throws {
        let seeds = [1, 2, 5, 7, 15, 42]
        let sheet = VStack(alignment: .leading, spacing: 16) {
            label("Blink phases - open / mid / shut, seeds \(seeds.map(String.init).joined(separator: ", "))")
            ForEach([0, 1, 2], id: \.self) { phase in
                HStack(alignment: .bottom, spacing: 12) {
                    Text(["open", "mid", "shut"][phase])
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 44, alignment: .leading)
                    ForEach(seeds, id: \.self) { seed in
                        self.figure(seed: seed, variant: .customer, phase: phase, w: 88, h: 124)
                    }
                }
            }

            label("Variants shut - customer / staff / golden / critic (glasses and monocle must survive)")
            HStack(alignment: .bottom, spacing: 12) {
                ForEach([SpriteVariant.customer, .staff, .golden, .critic], id: \.self) { v in
                    self.figure(seed: 7, variant: v, phase: 2, w: 110, h: 154)
                }
            }

            label("Actual queue size 44x62 - open then shut")
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(1...6, id: \.self) { self.figure(seed: $0, variant: .customer, phase: 0, w: 44, h: 62) }
                Spacer().frame(width: 20)
                ForEach(1...6, id: \.self) { self.figure(seed: $0, variant: .customer, phase: 2, w: 44, h: 62) }
            }
        }
        .padding(24)
        .background(Theme.ink)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            return XCTFail("ImageRenderer produced nothing")
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blink-contact-sheet.png")
        try data.write(to: url)
        print("BLINK_SHEET_PATH=\(url.path)")
    }

    // MARK: helpers

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textDim)
    }

    private func figure(seed: Int, variant: SpriteVariant, phase: Int,
                        w: CGFloat, h: CGFloat) -> some View {
        CustomerSprite(seed: seed, variant: variant).equatable()
            .overlay(BlinkOverlay(look: SpriteBlinkLook(seed: seed, variant: variant), phase: phase))
            .frame(width: w, height: h)
    }

    /// A rectangle in the 100 x 150 design frame.
    private struct DesignRect {
        let x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat
    }

    /// A patch of pupil, left of centre so it clears the catch-light (which sits at +0.8, -0.8
    /// from the eye centre with radius 0.85) and high enough to clear the lash curve the shut
    /// state draws, so it only ever samples pupil ink or the skin that replaces it.
    private func pupilProbe(side: CGFloat) -> DesignRect {
        let cx = 50 + side * SpriteFaceRig.eyeDX
        return DesignRect(x0: cx - 1.5, x1: cx - 0.4,
                          y0: SpriteFaceRig.eyeCY - 1.6, y1: SpriteFaceRig.eyeCY - 0.6)
    }

    /// The whole eye, pupil and lid travel and lash together.
    private func eyeSocket(side: CGFloat) -> DesignRect {
        let cx = 50 + side * SpriteFaceRig.eyeDX
        return DesignRect(x0: cx - SpriteFaceRig.eyeR, x1: cx + SpriteFaceRig.eyeR,
                          y0: SpriteFaceRig.eyeCY - SpriteFaceRig.eyeR,
                          y1: SpriteFaceRig.eyeCY + SpriteFaceRig.eyeR)
    }

    /// A decoded RGBA8 frame with design-space sampling on top.
    ///
    /// Row 0 of a `CGBitmapContext`'s buffer is the top of the image while its user-space
    /// origin is bottom-left; drawing the frame to fill the context means buffer row `r` is
    /// image row `r` counted downward, which lines up with design y directly.
    private struct Frame {
        let width: Int, height: Int
        let pixels: [UInt8]

        private func luminance(_ col: Int, _ row: Int) -> Double {
            let i = (row * width + col) * 4
            // Rec. 601 luma - ample to separate #332B36 pupil ink from any of the six skins.
            return (0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1])
                    + 0.114 * Double(pixels[i + 2])) / 255
        }

        private func columnsRows(_ r: DesignRect) -> (ClosedRange<Int>, ClosedRange<Int>) {
            let sx = Double(width) / Double(SpriteFaceRig.frameW)
            let sy = Double(height) / Double(SpriteFaceRig.frameH)
            let c0 = max(0, Int((Double(r.x0) * sx).rounded()))
            let c1 = min(width - 1, Int((Double(r.x1) * sx).rounded()))
            let r0 = max(0, Int((Double(r.y0) * sy).rounded()))
            let r1 = min(height - 1, Int((Double(r.y1) * sy).rounded()))
            return (c0...max(c0, c1), r0...max(r0, r1))
        }

        /// Share of pixels dark enough to be pupil ink rather than skin. The darkest skin tone
        /// (#5C3A24) sits at 0.27 luma and the pupil at 0.18, so the threshold splits them.
        func darkFraction(in rect: DesignRect) -> Double {
            let (cols, rows) = columnsRows(rect)
            var dark = 0, total = 0
            for row in rows {
                for col in cols {
                    total += 1
                    if luminance(col, row) < 0.23 { dark += 1 }
                }
            }
            return total == 0 ? 0 : Double(dark) / Double(total)
        }

        func meanLuminance(in rect: DesignRect) -> Double {
            let (cols, rows) = columnsRows(rect)
            var sum = 0.0, total = 0
            for row in rows {
                for col in cols {
                    sum += luminance(col, row)
                    total += 1
                }
            }
            return total == 0 ? 0 : sum / Double(total)
        }
    }

    private func bitmap(phase: Int, includeOverlay: Bool = true) throws -> Frame {
        let content = ZStack {
            // Opaque behind the figure so a sampled pixel is never blended against nothing.
            Rectangle().fill(Theme.ink)
            CustomerSprite(seed: blinkingSeed).equatable()
                .overlay {
                    if includeOverlay {
                        BlinkOverlay(look: SpriteBlinkLook(seed: blinkingSeed, variant: .customer),
                                     phase: phase)
                    }
                }
        }
        .frame(width: renderW, height: renderH)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            throw XCTSkip("ImageRenderer produced no CGImage on this runner")
        }

        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { throw XCTSkip("could not create a sampling context") }

        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return Frame(width: w, height: h, pixels: pixels)
    }
}
