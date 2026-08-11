import SwiftUI

/// Which figure a `CustomerSprite` is drawing.
///
/// `.golden` and `.critic` are their own outfit *tiers*, not recolors of a seeded shirt - the
/// engine already distinguishes them (`GoldenCustomer.isCritic`, a x10 jackpot) but until now
/// they rendered identically, so the player only learned which one they'd caught from the
/// toast *after* tapping. See `GoldenCustomerView`.
enum SpriteVariant: Equatable {
    case customer
    case staff
    case golden
    case critic
}

/// A procedurally drawn person, deterministic from a single `Int`.
///
/// Authored in design's 100 x 150 unit frame (x right, y down, feet at y 146) and mapped onto
/// the normalised `p()` convention by dividing x by 100 and y by 150 - `dp`/`dr`/`de` below do
/// that so every number in this file can be read straight off the art spec.
struct CustomerSprite: View, Equatable {
    let seed: Int
    var variant: SpriteVariant = .customer

    static func == (lhs: CustomerSprite, rhs: CustomerSprite) -> Bool {
        lhs.seed == rhs.seed && lhs.variant == rhs.variant
    }

    // Wardrobe. Unchanged from the original sprite on purpose: the seed slots that index these
    // arrays keep their bounds (see `Look.roll`), so every already-shipped customer and manager
    // portrait keeps the exact skin, hair, shirt and trouser colours it had before the rebuild.
    fileprivate static let skins = ["#F2C49B", "#D9A06B", "#A9714B", "#7A4E33", "#F7D9BE", "#5C3A24"]
    fileprivate static let hairs = ["#2E2A2B", "#5B3A20", "#C8873B", "#8E4A3C", "#3C4A6B", "#B8B2AD"]
    fileprivate static let shirts = ["#4C79C0", "#D4685A", "#57A773", "#C9A227", "#8367C7", "#3FA8A0", "#E08A50"]
    fileprivate static let pants = ["#37405C", "#2E3A2F", "#4A3A52", "#5C4632"]
    fileprivate static let hatColors = ["#E4453A", "#37405C", "#C9A227", "#2E3A2F"]

    fileprivate static let cream = "#F2EDE2"
    fileprivate static let eyeInk = "#332B36"
    fileprivate static let mouth = "#7C3644"

    /// The four wardrobe colours a seed resolves to.
    ///
    /// Exposed for `SpriteSeedTests`, which guards the one failure mode of this rebuild that
    /// has no visible symptom until it has already shipped: if these four draws ever shift,
    /// every customer and every collected manager portrait silently changes colour.
    static func wardrobeForTesting(seed: Int) -> (skin: String, hair: String, shirt: String, pants: String) {
        let look = Look(seed: seed, variant: .customer)
        return (look.skin, look.hair, look.torso, look.trousers)
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let outline = Theme.outline
            let line = max(1, rect.width * 0.04)
            let look = Look(seed: seed, variant: variant)

            // MARK: design-space helpers (100 x 150)

            func dp(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 150 * rect.height)
            }
            /// Stroke widths are quoted in design x-units, so they scale off width alone -
            /// scaling them off the smaller axis would thin every limb on a squat frame.
            func dw(_ w: CGFloat) -> CGFloat { w / 100 * rect.width }
            func de(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: rect.minX + (cx - rx) / 100 * rect.width,
                                       y: rect.minY + (cy - ry) / 150 * rect.height,
                                       width: 2 * rx / 100 * rect.width,
                                       height: 2 * ry / 150 * rect.height))
            }
            func dcircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                // A circle in design space, not an ellipse: radius keys off x so it stays round.
                let rr = r / 100 * rect.width
                return Path(ellipseIn: CGRect(x: dp(cx, cy).x - rr, y: dp(cx, cy).y - rr,
                                              width: rr * 2, height: rr * 2))
            }
            func drr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: rect.minX + x / 100 * rect.width,
                                         y: rect.minY + y / 150 * rect.height,
                                         width: w / 100 * rect.width,
                                         height: h / 150 * rect.height),
                     cornerRadius: radius / 100 * rect.width)
            }
            func path(_ build: (inout Path) -> Void) -> Path {
                var p = Path(); build(&p); return p
            }
            /// A half-ellipse dome, left to right over the top, continuing from the current
            /// point at `(cx - a, cy)`.
            ///
            /// Design authored these as SVG elliptical arcs. They cannot be `addArc`, which is
            /// always circular while this frame scales x and y independently - and a cheaper
            /// two-quad approximation sits noticeably flat at the sides, which left the spiky
            /// hairstyle's tufts protruding above the hairline instead of sitting in it.
            func dome(_ p: inout Path, cx: CGFloat, a: CGFloat, cy: CGFloat, b: CGFloat) {
                let k: CGFloat = 0.5523  // the standard cubic-Bezier ellipse constant
                p.addCurve(to: dp(cx, cy - b),
                           control1: dp(cx - a, cy - b * k), control2: dp(cx - a * k, cy - b))
                p.addCurve(to: dp(cx + a, cy),
                           control1: dp(cx + a * k, cy - b), control2: dp(cx + a, cy - b * k))
            }

            // MARK: the outline DNA
            //
            // Every filled part gets the #2B1D14 stroke; stroked limbs get a same-path underlay
            // in the outline colour, drawn first and fatter, which is what reads as a chunky
            // cartoon edge on a round-capped line. Detail layers (eyes, catch-lights, mouth,
            // blush, glasses, shading) deliberately skip it - see `overlay`.

            func fill(_ p: Path, _ hex: String, opacity: Double = 1) {
                context.fill(p, with: .color(Color(hex: hex).opacity(opacity)))
                context.stroke(p, with: .color(outline), lineWidth: line)
            }
            func overlay(_ p: Path, _ hex: String, opacity: Double = 1) {
                context.fill(p, with: .color(Color(hex: hex).opacity(opacity)))
            }
            func limb(_ p: Path, _ hex: String, width: CGFloat) {
                context.stroke(p, with: .color(outline),
                               style: StrokeStyle(lineWidth: dw(width) + line, lineCap: .round))
                context.stroke(p, with: .color(Color(hex: hex)),
                               style: StrokeStyle(lineWidth: dw(width), lineCap: .round))
            }
            func hairline(_ p: Path, _ hex: String, width: CGFloat, opacity: Double = 1) {
                context.stroke(p, with: .color(Color(hex: hex).opacity(opacity)),
                               style: StrokeStyle(lineWidth: dw(width), lineCap: .round))
            }

            // MARK: rig geometry
            //
            // Heights never vary - only widths - so a mixed-build queue still shares one
            // baseline and reads as a row of people standing on the same floor.
            let bw = [0.86, 1.0, 1.17][look.build]
            let headCY: CGFloat = 34
            let headRX: CGFloat = 22.5 + (look.build == 2 ? 1.5 : (look.build == 0 ? -1.5 : 0))
            let headRY: CGFloat = 20.5
            let neckY: CGFloat = 50, neckW: CGFloat = 10
            let shoulderY: CGFloat = 61, hipY: CGFloat = 103
            let sw = 20 * bw, hw = 14.5 * bw
            let legTop: CGFloat = 101, legBottom: CGFloat = 135
            let handR: CGFloat = 4.6, armW: CGFloat = 7.5
            let headTop = headCY - headRY

            let isDress = look.outfit == .dress
            let legColor = isDress ? look.skin : look.trousers

            // 1. Back hair, behind the head - the only hair mass that draws under the body.
            if look.hairstyle == 1 {
                fill(path {
                    $0.move(to: dp(50 - headRX - 2, headCY - 5))
                    $0.addQuadCurve(to: dp(50 - headRX + 3, headCY + headRY + 4),
                                    control: dp(50 - headRX - 5, headCY + headRY))
                    $0.addLine(to: dp(50 - headRX + 7, headCY))
                    $0.closeSubpath()
                }, look.hair)
                fill(path {
                    $0.move(to: dp(50 + headRX + 2, headCY - 5))
                    $0.addQuadCurve(to: dp(50 + headRX - 3, headCY + headRY + 4),
                                    control: dp(50 + headRX + 5, headCY + headRY))
                    $0.addLine(to: dp(50 + headRX - 7, headCY))
                    $0.closeSubpath()
                }, look.hair)
            }

            // 2. Legs and shoes.
            let lx = 50 - hw + 4.5, rx = 50 + hw - 4.5
            limb(path { $0.move(to: dp(lx, legTop)); $0.addLine(to: dp(lx, legBottom)) },
                 legColor, width: armW + 1.5)
            limb(path { $0.move(to: dp(rx, legTop)); $0.addLine(to: dp(rx, legBottom)) },
                 legColor, width: armW + 1.5)
            fill(de(lx - 1, legBottom + 3.5, 6.2, 4), Self.eyeInk)
            fill(de(rx + 1, legBottom + 3.5, 6.2, 4), Self.eyeInk)

            // 3. Torso: a trapezoid from shoulders down to hips, corners rounded with quads.
            fill(path {
                $0.move(to: dp(50 - sw + 5, shoulderY))
                $0.addQuadCurve(to: dp(50 - sw, shoulderY + 7), control: dp(50 - sw, shoulderY))
                $0.addLine(to: dp(50 - hw, hipY - 6))
                $0.addQuadCurve(to: dp(50 - hw + 6, hipY), control: dp(50 - hw, hipY))
                $0.addLine(to: dp(50 + hw - 6, hipY))
                $0.addQuadCurve(to: dp(50 + hw, hipY - 6), control: dp(50 + hw, hipY))
                $0.addLine(to: dp(50 + sw, shoulderY + 7))
                $0.addQuadCurve(to: dp(50 + sw - 5, shoulderY), control: dp(50 + sw, shoulderY))
                $0.closeSubpath()
            }, look.torso)

            // 4. Outfit detailing over the torso.
            switch look.outfit {
            case .dress:
                fill(path {
                    $0.move(to: dp(50 - hw, hipY - 13))
                    $0.addLine(to: dp(50 - hw - 8, hipY + 12))
                    $0.addQuadCurve(to: dp(50 + hw + 8, hipY + 12), control: dp(50, hipY + 19))
                    $0.addLine(to: dp(50 + hw, hipY - 13))
                    $0.closeSubpath()
                }, look.torso)
            case .jacket:
                hairline(path { $0.move(to: dp(50, shoulderY + 3)); $0.addLine(to: dp(50, hipY - 3)) },
                         "#000000", width: 2, opacity: 0.28)
                hairline(path {
                    $0.move(to: dp(43, shoulderY + 1))
                    $0.addLine(to: dp(50, shoulderY + 9))
                    $0.addLine(to: dp(57, shoulderY + 1))
                }, "#FFFFFF", width: 2.5, opacity: 0.4)
            case .apron:
                overlay(path {
                    $0.move(to: dp(50 - 8 * bw, shoulderY + 9))
                    $0.addLine(to: dp(50 + 8 * bw, shoulderY + 9))
                    $0.addLine(to: dp(50 + hw - 3.5, hipY - 2))
                    $0.addLine(to: dp(50 - hw + 3.5, hipY - 2))
                    $0.closeSubpath()
                }, look.apron)
                hairline(path {
                    $0.move(to: dp(50 - 8 * bw, shoulderY + 9))
                    $0.addQuadCurve(to: dp(50 + 8 * bw, shoulderY + 9), control: dp(50, shoulderY + 2))
                }, look.apron, width: 2.4)
                overlay(drr(45, (shoulderY + hipY) / 2, 10, 7, 1.5), "#000000", opacity: 0.15)
            case .tee:
                break
            }

            // Golden and critic get their tier's trim on top of the base coat.
            if variant == .golden {
                hairline(path {
                    $0.move(to: dp(50 - 9, shoulderY + 2))
                    $0.addLine(to: dp(50, shoulderY + 11))
                    $0.addLine(to: dp(50 + 9, shoulderY + 2))
                }, "#FFE9A8", width: 3)
                for i in 0..<3 {
                    overlay(dcircle(50, shoulderY + 17 + CGFloat(i) * 10, 1.9), "#FFE9A8")
                }
            }
            if variant == .critic {
                // Lapels, then the bow tie at the collar - the silhouette cues that separate a
                // x10 critic from an ordinary golden before the payout resolves.
                hairline(path {
                    $0.move(to: dp(50 - 8, shoulderY + 1))
                    $0.addLine(to: dp(50, shoulderY + 12))
                    $0.addLine(to: dp(50 + 8, shoulderY + 1))
                }, "#F5C242", width: 2.6)
                fill(path {
                    $0.move(to: dp(50 - 7, shoulderY + 1))
                    $0.addLine(to: dp(50 - 1, shoulderY + 5))
                    $0.addLine(to: dp(50 - 7, shoulderY + 9))
                    $0.closeSubpath()
                }, "#F5C242")
                fill(path {
                    $0.move(to: dp(50 + 7, shoulderY + 1))
                    $0.addLine(to: dp(50 + 1, shoulderY + 5))
                    $0.addLine(to: dp(50 + 7, shoulderY + 9))
                    $0.closeSubpath()
                }, "#F5C242")
            }

            // 5. Arms. Two segments each, so a raised arm can actually hold something.
            let shoulderPointY = shoulderY + 5.5
            let bareForearm = look.outfit == .tee || isDress

            @discardableResult
            func arm(_ m: CGFloat, raised: Bool) -> CGPoint {
                let sx = 50 + m * (sw - 2)
                if raised {
                    limb(path {
                        $0.move(to: dp(sx, shoulderPointY))
                        $0.addQuadCurve(to: dp(50 + m * (sw + 8), shoulderPointY + 12),
                                        control: dp(50 + m * (sw + 7), shoulderPointY + 6))
                    }, look.sleeve, width: armW + 1)
                    limb(path {
                        $0.move(to: dp(50 + m * (sw + 8), shoulderPointY + 12))
                        $0.addQuadCurve(to: dp(50 + m * (sw + 10), shoulderPointY - 4),
                                        control: dp(50 + m * (sw + 11), shoulderPointY + 4))
                    }, bareForearm ? look.skin : look.sleeve, width: armW - 0.5)
                    fill(dcircle(50 + m * (sw + 10), shoulderPointY - 6, handR), look.skin)
                    return CGPoint(x: 50 + m * (sw + 10), y: shoulderPointY - 6)
                }
                limb(path {
                    $0.move(to: dp(sx, shoulderPointY))
                    $0.addQuadCurve(to: dp(50 + m * (sw + 5), shoulderPointY + 16),
                                    control: dp(50 + m * (sw + 6), shoulderPointY + 9))
                }, look.sleeve, width: armW + 1)
                limb(path {
                    $0.move(to: dp(50 + m * (sw + 5), shoulderPointY + 16))
                    $0.addQuadCurve(to: dp(50 + m * (sw + 2), shoulderPointY + 30),
                                    control: dp(50 + m * (sw + 6), shoulderPointY + 24))
                }, bareForearm ? look.skin : look.sleeve, width: armW - 0.5)
                fill(dcircle(50 + m * (sw + 2), shoulderPointY + 31, handR), look.skin)
                return CGPoint(x: 50 + m * (sw + 2), y: shoulderPointY + 31)
            }

            arm(-1, raised: false)
            let handPoint = arm(1, raised: look.prop != nil)

            // 6. Neck, then head.
            fill(drr(50 - neckW / 2, neckY, neckW, (shoulderY - neckY) + 5, 2.5), look.skin)
            fill(de(50, headCY, headRX, headRY), look.skin)

            // 7. Face. Eyes sit slightly high in the head; both catch-lights are offset the
            // same way, as if lit from one source, which is what stops them reading as googly.
            if look.face == 2 {
                hairline(path {
                    $0.move(to: dp(50 - 10, headCY + 1))
                    $0.addQuadCurve(to: dp(50 - 4, headCY + 1), control: dp(50 - 7, headCY - 3.5))
                }, Self.eyeInk, width: 1.8)
                hairline(path {
                    $0.move(to: dp(50 + 4, headCY + 1))
                    $0.addQuadCurve(to: dp(50 + 10, headCY + 1), control: dp(50 + 7, headCY - 3.5))
                }, Self.eyeInk, width: 1.8)
            } else {
                overlay(dcircle(50 - 7, headCY + 0.5, 2.3), Self.eyeInk)
                overlay(dcircle(50 + 7, headCY + 0.5, 2.3), Self.eyeInk)
                overlay(dcircle(50 - 6.2, headCY - 0.3, 0.85), "#FFFFFF")
                overlay(dcircle(50 + 7.8, headCY - 0.3, 0.85), "#FFFFFF")
            }
            if look.face == 1 {
                overlay(de(50, headCY + 8.5, 2.8, 3.4), Self.mouth)
            } else {
                hairline(path {
                    $0.move(to: dp(50 - 4.5, headCY + 7.5))
                    $0.addQuadCurve(to: dp(50 + 4.5, headCY + 7.5), control: dp(50, headCY + 11.5))
                }, Self.mouth, width: 1.8)
            }
            if look.blush {
                overlay(dcircle(50 - 11, headCY + 5, 2.3), "#E4453A", opacity: 0.26)
                overlay(dcircle(50 + 11, headCY + 5, 2.3), "#E4453A", opacity: 0.26)
            }

            // 8. Hair. The cap mass is shared; styles add to it rather than replacing it, so a
            // hat can always sit on top without erasing the hairline underneath.
            let sym = path {
                $0.move(to: dp(50 - headRX - 1, headCY - 2))
                dome(&$0, cx: 50, a: headRX + 1, cy: headCY - 2, b: headRY + 1.5)
                $0.addQuadCurve(to: dp(50, headTop + 9), control: dp(50 + headRX - 4, headTop + 10))
                $0.addQuadCurve(to: dp(50 - headRX - 1, headCY - 2), control: dp(50 - headRX + 4, headTop + 10))
                $0.closeSubpath()
            }
            let swoop = path {
                $0.move(to: dp(50 - headRX - 1, headCY - 2))
                dome(&$0, cx: 50, a: headRX + 1, cy: headCY - 2, b: headRY + 1.5)
                $0.addQuadCurve(to: dp(55, headTop + 7), control: dp(50 + headRX - 2, headTop + 12))
                $0.addQuadCurve(to: dp(50 - headRX - 1, headCY - 2), control: dp(50 - headRX + 7, headTop + 5))
                $0.closeSubpath()
            }
            fill(look.hairstyle == 4 ? swoop : sym, look.hair)
            if look.hairstyle == 2 {
                // Design drew this as a symmetric three-point zigzag. Rendered, that is a crown
                // silhouette - and a crown is this game's signal for "VIP, tap me for a big
                // payout" (see `GoldenCustomerView`). Nearly a fifth of all seeds roll this
                // style, so a fifth of ordinary customers were wearing what reads as regalia.
                // Same idea, deliberately asymmetric and with shallower notches, so it reads as
                // tousled hair and leaves the crown meaning something.
                fill(path {
                    $0.move(to: dp(50 - headRX * 0.68, headTop + 6))
                    $0.addLine(to: dp(50 - headRX * 0.55, headTop - 4))
                    $0.addLine(to: dp(50 - 8, headTop + 1.5))
                    $0.addLine(to: dp(50 - 1, headTop - 6))
                    $0.addLine(to: dp(50 + 6, headTop + 0.5))
                    $0.addLine(to: dp(50 + 12, headTop - 4.5))
                    $0.addLine(to: dp(50 + headRX * 0.6, headTop + 2.5))
                    $0.addLine(to: dp(50 + headRX * 0.7, headTop + 6))
                    $0.closeSubpath()
                }, look.hair)
            }
            if look.hairstyle == 3 {
                fill(dcircle(50, headTop - 3, 5.5), look.hair)
            }

            // 9. Hat, over the hair.
            switch look.hat {
            case 1: // ball cap
                fill(path {
                    $0.move(to: dp(50 - headRX - 1, headCY - 6))
                    dome(&$0, cx: 50, a: headRX + 1, cy: headCY - 6, b: headRY - 2)
                    $0.closeSubpath()
                }, look.hatColor)
                hairline(path {
                    $0.move(to: dp(50 - headRX + 2, headCY - 5))
                    $0.addQuadCurve(to: dp(50 + headRX - 2, headCY - 5), control: dp(50, headCY + 4))
                }, look.hatColor, width: 3.5)
                fill(dcircle(50, headTop - 3, 2.4), look.hatColor)
            case 2: // folded paper hat - the kitchen tell
                fill(path {
                    $0.move(to: dp(39, headTop + 5))
                    $0.addLine(to: dp(41, headTop - 9))
                    $0.addLine(to: dp(61, headTop - 7))
                    $0.addLine(to: dp(59, headTop + 7))
                    $0.closeSubpath()
                }, Self.cream)
                hairline(path {
                    $0.move(to: dp(41, headTop - 1))
                    $0.addLine(to: dp(59, headTop))
                }, "#E4453A", width: 1.6, opacity: 0.7)
            case 3: // beanie
                fill(path {
                    $0.move(to: dp(50 - headRX, headCY - 5))
                    dome(&$0, cx: 50, a: headRX, cy: headCY - 5, b: headRY)
                    $0.closeSubpath()
                }, look.hatColor)
                overlay(drr(50 - headRX, headCY - 9, headRX * 2, 5, 2), "#FFFFFF", opacity: 0.35)
                fill(dcircle(50, headTop - 4, 4), look.hatColor)
            default:
                break
            }

            // 10. Accessories.
            if look.accessory == 1 {
                hairline(dcircle(50 - 7, headCY + 0.5, 4.8), Self.eyeInk, width: 1.6)
                hairline(dcircle(50 + 7, headCY + 0.5, 4.8), Self.eyeInk, width: 1.6)
                hairline(path {
                    $0.move(to: dp(47.8, headCY)); $0.addLine(to: dp(52.2, headCY))
                }, Self.eyeInk, width: 1.6)
            }
            if look.accessory == 2 {
                overlay(drr(50 + hw - 10, shoulderY + 8, 8.5, 6, 1.2), "#F6F1E6")
                hairline(path {
                    $0.move(to: dp(50 + hw - 8, shoulderY + 11)); $0.addLine(to: dp(50 + hw - 3.5, shoulderY + 11))
                }, "#8A8A94", width: 1)
            }

            // The critic's monocle and chain go over the glasses slot, never beside it.
            if variant == .critic {
                hairline(dcircle(50 + 7, headCY + 0.5, 5), "#F5C242", width: 1.8)
                hairline(path {
                    $0.move(to: dp(50 + 12, headCY + 3))
                    $0.addQuadCurve(to: dp(50 + 15, headCY + 16), control: dp(50 + 16, headCY + 9))
                }, "#F5C242", width: 1.2)
            }

            // 11. Held prop, anchored to whichever hand was raised.
            switch look.prop {
            case .spatula:
                limb(path {
                    $0.move(to: dp(handPoint.x, handPoint.y - 3))
                    $0.addLine(to: dp(handPoint.x + 2, handPoint.y - 18))
                }, "#9A9AA6", width: 2.6)
                fill(drr(handPoint.x - 3, handPoint.y - 29, 10, 11, 3), "#C4C4CE")
            case .tray:
                fill(de(handPoint.x + 1, handPoint.y - 4, 13, 3.6), "#C4C4CE")
                fill(drr(handPoint.x - 4, handPoint.y - 14, 9, 9, 2), "#F6F1E6")
            case .cup:
                fill(drr(handPoint.x - 4, handPoint.y - 15, 9, 12, 2), "#F6F1E6")
                fill(drr(handPoint.x - 5, handPoint.y - 17, 11, 3, 1), "#E4453A")
            case .clipboard:
                fill(drr(handPoint.x - 6, handPoint.y - 22, 14, 18, 2), "#8A6444")
                fill(drr(handPoint.x - 4, handPoint.y - 20, 10, 14, 1), "#F6F1E6")
                for i in 0..<3 {
                    hairline(path {
                        $0.move(to: dp(handPoint.x - 2, handPoint.y - 16 + CGFloat(i) * 4))
                        $0.addLine(to: dp(handPoint.x + (i == 2 ? 2 : 4), handPoint.y - 16 + CGFloat(i) * 4))
                    }, "#8A8A94", width: 1.2)
                }
            case .none:
                break
            }

            // 12. Crown, for the two VIP tiers. Sits above the head rather than on it, so it
            // never fights the hair silhouette.
            if variant == .golden || variant == .critic {
                let crownBase = headTop - 5, crownTop = headTop - 15
                fill(path {
                    $0.move(to: dp(37, crownBase))
                    $0.addLine(to: dp(37, crownTop + 3))
                    $0.addLine(to: dp(43, crownTop + 7))
                    $0.addLine(to: dp(50, crownTop))
                    $0.addLine(to: dp(57, crownTop + 7))
                    $0.addLine(to: dp(63, crownTop + 3))
                    $0.addLine(to: dp(63, crownBase))
                    $0.closeSubpath()
                }, "#F5C242")
                fill(drr(36, crownBase - 1, 28, 4, 1.5), "#FFE9A8")
                for x in [43, 50, 57] {
                    overlay(dcircle(CGFloat(x), crownBase - 4, 1.4), "#E4453A")
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Seeded look

/// Everything the rig needs, rolled from one seed.
///
/// **The draw order below is load-bearing.** `SeededRandom` is a stateful xorshift, so each
/// `next` call advances it whether or not the bound changed. Drawing the original seven slots
/// first, in their shipping order, is what keeps slots 1-4 bit-identical: `next(3)` and
/// `next(5)` consume exactly one step each, so widening a bound changes only that slot's own
/// value and leaves everything downstream on the same sequence. Every customer and manager
/// portrait therefore keeps its skin, hair, shirt and trouser colours across this rebuild;
/// hairstyle, outfit and hat re-roll once, and slots 8-12 are new.
private struct Look {
    enum Outfit { case tee, apron, jacket, dress }
    enum Prop { case spatula, tray, cup, clipboard }

    var skin = "", hair = "", torso = "", trousers = "", sleeve = ""
    var apron = CustomerSprite.cream
    var hatColor = ""
    var hairstyle = 0, hat = 0, face = 0, accessory = 0, build = 1
    var blush = false
    var outfit: Outfit = .tee
    var prop: Prop?

    init(seed: Int, variant: SpriteVariant) {
        let rng = SeededRandom(seed: seed)

        // --- original seven, in shipping order ---
        skin = CustomerSprite.skins[rng.next(CustomerSprite.skins.count)]
        hair = CustomerSprite.hairs[rng.next(CustomerSprite.hairs.count)]
        let shirt = CustomerSprite.shirts[rng.next(CustomerSprite.shirts.count)]
        trousers = CustomerSprite.pants[rng.next(CustomerSprite.pants.count)]
        hairstyle = rng.next(5)
        outfit = [.tee, .apron, .jacket, .dress][rng.next(4)]
        // The style draw is only consumed when the gate opens, exactly as design specified -
        // so hatted and bare-headed figures legitimately consume different numbers of draws.
        hat = rng.next(4) == 0 ? 1 + rng.next(3) : 0

        // --- new slots ---
        hatColor = CustomerSprite.hatColors[rng.next(CustomerSprite.hatColors.count)]
        build = rng.next(3)
        face = rng.next(3)
        accessory = [0, 1, 2, 0][rng.next(4)]
        blush = rng.next(4) < 2

        torso = shirt
        sleeve = shirt

        switch variant {
        case .customer:
            break
        case .staff:
            // The job has to read off the figure alone, so staff are forced into the uniform
            // rather than left to the roll.
            outfit = .apron
            apron = CustomerSprite.cream
            hat = 2
            prop = [.spatula, .tray, .cup][rng.next(3)]
        case .golden:
            outfit = .jacket
            torso = "#F5C242"
            sleeve = "#F5C242"
            trousers = "#8A6A2A"
            hat = 0
        case .critic:
            outfit = .jacket
            torso = "#4A3566"
            sleeve = "#4A3566"
            trousers = "#2E2340"
            hat = 0
            accessory = 0
            prop = .clipboard
        }
    }
}

// MARK: - Rarity frame

/// A rarity-tiered frame for a manager portrait.
///
/// Complexity escalates rather than just hue, so the tier reads before colour registers:
/// plain ring, then a faceted inner dash, then a fake-bloom outer glow, then the legendary
/// highlight arc and crest. The highlight is parked at -90 (12 o'clock) rather than rotating -
/// the motion pass is deliberately deferred, and this is design's own reduce-motion pose.
struct ManagerRarityFrame: View {
    let rarity: ManagerRarity

    private var ringColor: Color {
        switch rarity {
        case .common: return Color(hex: "#B3A8C0")
        case .rare: return Theme.gem
        case .epic: return Color(hex: "#B07BE8")
        case .legendary: return Theme.star
        }
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let w = rect.width

            func ring(inset: CGFloat) -> Path {
                Path(ellipseIn: rect.insetBy(dx: inset, dy: inset))
            }

            let disc = ring(inset: w * 0.02)
            context.fill(disc, with: .color(Theme.panel))
            context.stroke(disc, with: .color(Theme.outline), lineWidth: max(1, w * 0.035))

            // Epic and up get the glowDot trick - widening, fading strokes reading as bloom with
            // no blur filter anywhere. Design put the bloom outside the ring; it lives just
            // inside it here because the Canvas clips to its own bounds and all three call sites
            // wrap this in a `.clipShape(Circle())`, so an outer halo would simply be cut off.
            if rarity >= .epic {
                context.stroke(ring(inset: w * 0.095), with: .color(ringColor.opacity(0.18)),
                               lineWidth: w * 0.07)
                context.stroke(ring(inset: w * 0.055), with: .color(ringColor.opacity(0.32)),
                               lineWidth: w * 0.055)
            }

            context.stroke(disc, with: .color(ringColor), lineWidth: w * 0.05)

            if rarity >= .rare {
                context.stroke(ring(inset: w * 0.055), with: .color(ringColor.opacity(0.85)),
                               style: StrokeStyle(lineWidth: w * 0.025,
                                                  dash: [w * 0.07, w * 0.1]))
            }

            if rarity == .legendary {
                var highlight = ring(inset: w * 0.02)
                highlight = highlight.applying(
                    CGAffineTransform(translationX: rect.midX, y: rect.midY)
                        .rotated(by: -.pi / 2)
                        .translatedBy(x: -rect.midX, y: -rect.midY))
                context.stroke(highlight, with: .color(Color(hex: "#FFF3C4")),
                               style: StrokeStyle(lineWidth: w * 0.05, lineCap: .round,
                                                  dash: [w * 0.32, w * 1.9]))
                var crest = Path()
                crest.move(to: CGPoint(x: rect.midX, y: rect.minY + w * 0.01))
                crest.addLine(to: CGPoint(x: rect.midX + w * 0.035, y: rect.minY + w * 0.075))
                crest.addLine(to: CGPoint(x: rect.midX + w * 0.1, y: rect.minY + w * 0.1))
                crest.addLine(to: CGPoint(x: rect.midX + w * 0.035, y: rect.minY + w * 0.125))
                crest.addLine(to: CGPoint(x: rect.midX, y: rect.minY + w * 0.19))
                crest.addLine(to: CGPoint(x: rect.midX - w * 0.035, y: rect.minY + w * 0.125))
                crest.addLine(to: CGPoint(x: rect.midX - w * 0.1, y: rect.minY + w * 0.1))
                crest.addLine(to: CGPoint(x: rect.midX - w * 0.035, y: rect.minY + w * 0.075))
                crest.closeSubpath()
                context.fill(crest, with: .color(Color(hex: "#FFE9A8")))
                context.stroke(crest, with: .color(Theme.outline), lineWidth: max(1, w * 0.02))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - RNG

/// XORShift64. Deliberately unchanged - the whole seed-compatibility argument in `Look` rests
/// on this producing the exact same stream it always has.
final class SeededRandom {
    private var state: UInt64

    init(seed: Int) { state = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 1) | 1 }

    func next(_ upperBound: Int) -> Int {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return upperBound > 0 ? Int(state % UInt64(upperBound)) : 0
    }
}
