import SwiftUI

/// A procedurally varied little person, composited from the visual-refresh asset pack's
/// modular character parts (body, head, 3 hairstyles, 1 hat, 3 outfits). One seed drives
/// every choice so a queue of customers - or a roster of managers - reads as a crowd instead
/// of a row of clones.
///
/// The hair/hat assets are authored against a head circle at `cx 50, cy 48, r 36` in their
/// own 100-unit frame (per the asset pack's registration convention); this composite instead
/// places the head at the top of a full standing figure, so hair/hat coordinates are
/// rescaled from their own registration circle onto this file's head placement via `hp(_:_:)`
/// - a uniform scale+translate that preserves each part's authored proportions.
struct CustomerSprite: View, Equatable {
    let seed: Int

    static func == (lhs: CustomerSprite, rhs: CustomerSprite) -> Bool { lhs.seed == rhs.seed }

    private static let skins = ["#F2C49B", "#D9A06B", "#A9714B", "#7A4E33", "#F7D9BE", "#5C3A24"]
    private static let hairs = ["#2E2A2B", "#5B3A20", "#C8873B", "#8E4A3C", "#3C4A6B", "#B8B2AD"]
    private static let shirts = ["#4C79C0", "#D4685A", "#57A773", "#C9A227", "#8367C7", "#3FA8A0", "#E08A50"]
    private static let pants = ["#37405C", "#2E3A2F", "#4A3A52", "#5C4632"]
    private static let cream = Color(hex: "#F2EDE2")

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let outline = Color(hex: "#2B1D14")
            let line = max(1, rect.width * 0.04)

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                       width: w * rect.width, height: h * rect.height)
            }
            func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                Path(roundedRect: r(x, y, w, h), cornerRadius: radius * rect.width)
            }
            func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(ellipseIn: r(x, y, w, h))
            }
            func rotated(_ path: Path, _ angle: Double, _ ax: CGFloat, _ ay: CGFloat) -> Path {
                let pivot = p(ax, ay)
                let t = CGAffineTransform(translationX: pivot.x, y: pivot.y)
                    .rotated(by: angle * .pi / 180)
                    .translatedBy(x: -pivot.x, y: -pivot.y)
                return path.applying(t)
            }
            func custom(_ build: (inout Path) -> Void) -> Path {
                var path = Path(); build(&path); return path
            }
            func fill(_ path: Path, _ color: Color, stroked: Bool = true) {
                context.fill(path, with: .color(color))
                if stroked { context.stroke(path, with: .color(outline), lineWidth: line) }
            }
            func overlay(_ path: Path, _ color: Color) { context.fill(path, with: .color(color)) }

            // Hair/hat are authored against a head at (50, 48, r36); this figure's head sits
            // higher and smaller, at (50, 22, r20). `hp` rescales one registration onto the
            // other so every hairstyle keeps its authored proportions.
            let srcCX: CGFloat = 0.50, srcCY: CGFloat = 0.48, srcR: CGFloat = 0.36
            let headCX: CGFloat = 0.50, headCY: CGFloat = 0.22, headR: CGFloat = 0.20
            let hairScale = headR / srcR
            func hp(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                p(headCX + (x - srcCX) * hairScale, headCY + (y - srcCY) * hairScale)
            }
            func hr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                let topLeft = hp(x, y)
                return CGRect(x: topLeft.x, y: topLeft.y, width: w * hairScale * rect.width,
                              height: h * hairScale * rect.height)
            }

            let rng = SeededRandom(seed: seed)
            let skin = Color(hex: Self.skins[rng.next(Self.skins.count)])
            let hair = Color(hex: Self.hairs[rng.next(Self.hairs.count)])
            let shirt = Color(hex: Self.shirts[rng.next(Self.shirts.count)])
            let trouser = Color(hex: Self.pants[rng.next(Self.pants.count)])
            let hairStyle = rng.next(3)
            let outfitStyle = rng.next(3)
            let hasHat = rng.next(4) == 0

            // MARK: Legs
            fill(rounded(0.36, 0.66, 0.12, 0.26, 0.06), trouser)
            fill(rounded(0.52, 0.66, 0.12, 0.26, 0.06), trouser)

            // MARK: Torso + outfit (each outfit supplies its own torso fill and shading)
            let torso = custom { path in
                path.move(to: p(0.30, 0.34))
                path.addQuadCurve(to: p(0.40, 0.26), control: p(0.30, 0.26))
                path.addLine(to: p(0.60, 0.26))
                path.addQuadCurve(to: p(0.70, 0.34), control: p(0.70, 0.26))
                path.addLine(to: p(0.70, 0.62))
                path.addQuadCurve(to: p(0.58, 0.72), control: p(0.70, 0.72))
                path.addLine(to: p(0.42, 0.72))
                path.addQuadCurve(to: p(0.30, 0.62), control: p(0.30, 0.72))
                path.closeSubpath()
            }
            let torsoShade = custom { path in
                path.move(to: p(0.62, 0.28))
                path.addQuadCurve(to: p(0.70, 0.38), control: p(0.70, 0.30))
                path.addLine(to: p(0.70, 0.62))
                path.addQuadCurve(to: p(0.58, 0.72), control: p(0.70, 0.72))
                path.addLine(to: p(0.50, 0.72))
                path.addQuadCurve(to: p(0.62, 0.56), control: p(0.62, 0.68))
                path.closeSubpath()
            }
            switch outfitStyle {
            case 0: // short sleeves + V-neck
                fill(custom { path in
                    path.move(to: p(0.30, 0.34))
                    path.addQuadCurve(to: p(0.20, 0.46), control: p(0.22, 0.34))
                    path.addQuadCurve(to: p(0.26, 0.52), control: p(0.19, 0.52))
                    path.addLine(to: p(0.34, 0.46)); path.closeSubpath()
                }, shirt)
                fill(custom { path in
                    path.move(to: p(0.70, 0.34))
                    path.addQuadCurve(to: p(0.80, 0.46), control: p(0.78, 0.34))
                    path.addQuadCurve(to: p(0.74, 0.52), control: p(0.81, 0.52))
                    path.addLine(to: p(0.66, 0.46)); path.closeSubpath()
                }, shirt)
                fill(torso, shirt)
                context.stroke(custom { path in
                    path.move(to: p(0.42, 0.26))
                    path.addQuadCurve(to: p(0.58, 0.26), control: p(0.50, 0.36))
                }, with: .color(outline), lineWidth: line * 0.85)
                overlay(torsoShade, outline.opacity(0.12))
                overlay(rotated(ellipse(0.335, 0.375, 0.05, 0.09), -6, 0.38, 0.42), Color.white.opacity(0.2))

            case 1: // apron/bib
                fill(torso, shirt)
                context.stroke(custom { path in
                    path.move(to: p(0.44, 0.27)); path.addLine(to: p(0.40, 0.40))
                }, with: .color(Self.cream), lineWidth: line)
                context.stroke(custom { path in
                    path.move(to: p(0.56, 0.27)); path.addLine(to: p(0.60, 0.40))
                }, with: .color(Self.cream), lineWidth: line)
                fill(custom { path in
                    path.move(to: p(0.38, 0.38)); path.addLine(to: p(0.62, 0.38))
                    path.addLine(to: p(0.62, 0.62))
                    path.addQuadCurve(to: p(0.54, 0.72), control: p(0.62, 0.72))
                    path.addLine(to: p(0.46, 0.72))
                    path.addQuadCurve(to: p(0.38, 0.62), control: p(0.38, 0.72))
                    path.closeSubpath()
                }, Self.cream)
                overlay(rounded(0.43, 0.50, 0.14, 0.10, 0.02), outline.opacity(0.14))
                overlay(custom { path in
                    path.move(to: p(0.56, 0.40)); path.addLine(to: p(0.62, 0.40))
                    path.addLine(to: p(0.62, 0.62))
                    path.addQuadCurve(to: p(0.54, 0.72), control: p(0.62, 0.72))
                    path.addLine(to: p(0.48, 0.72))
                    path.addQuadCurve(to: p(0.56, 0.66), control: p(0.56, 0.56))
                    path.closeSubpath()
                }, outline.opacity(0.1))
                overlay(torsoShade, outline.opacity(0.12))

            default: // scalloped yoke
                fill(torso, shirt)
                fill(custom { path in
                    path.move(to: p(0.36, 0.26))
                    path.addQuadCurve(to: p(0.64, 0.26), control: p(0.50, 0.44))
                    path.addQuadCurve(to: p(0.60, 0.38), control: p(0.66, 0.34))
                    path.addQuadCurve(to: p(0.40, 0.38), control: p(0.50, 0.44))
                    path.addQuadCurve(to: p(0.36, 0.26), control: p(0.34, 0.34))
                    path.closeSubpath()
                }, shirt)
                context.stroke(custom { path in
                    path.move(to: p(0.44, 0.38)); path.addLine(to: p(0.44, 0.46))
                }, with: .color(Self.cream), lineWidth: line * 0.85)
                context.stroke(custom { path in
                    path.move(to: p(0.56, 0.38)); path.addLine(to: p(0.56, 0.46))
                }, with: .color(Self.cream), lineWidth: line * 0.85)
                overlay(custom { path in
                    path.move(to: p(0.36, 0.54)); path.addLine(to: p(0.64, 0.54))
                    path.addLine(to: p(0.64, 0.62))
                    path.addQuadCurve(to: p(0.58, 0.68), control: p(0.64, 0.68))
                    path.addLine(to: p(0.42, 0.68))
                    path.addQuadCurve(to: p(0.36, 0.62), control: p(0.36, 0.68))
                    path.closeSubpath()
                }, outline.opacity(0.14))
                overlay(torsoShade, outline.opacity(0.12))
            }

            // MARK: Arms + hands
            fill(rounded(0.19, 0.34, 0.14, 0.30, 0.07), skin)
            fill(rounded(0.66, 0.34, 0.14, 0.30, 0.07), skin)
            fill(ellipse(0.19, 0.68, 0.12, 0.12), skin)
            fill(ellipse(0.69, 0.68, 0.12, 0.12), skin)

            // MARK: Head
            fill(ellipse(headCX - headR, headCY - headR, headR * 2, headR * 2), skin)
            overlay(custom { path in
                path.move(to: hp(0.16, 0.56))
                path.addQuadCurve(to: hp(0.50, 0.84), control: hp(0.22, 0.82))
                path.addQuadCurve(to: hp(0.84, 0.56), control: hp(0.78, 0.82))
                path.addQuadCurve(to: hp(0.50, 0.84), control: hp(0.82, 0.84))
                path.addQuadCurve(to: hp(0.16, 0.56), control: hp(0.18, 0.84))
                path.closeSubpath()
            }, outline.opacity(0.12))
            overlay(rotated(Path(ellipseIn: hr(0.22, 0.24, 0.24, 0.12)), -30, hp(0.34, 0.30).x, hp(0.34, 0.30).y), Color.white.opacity(0.24))
            overlay(Path(ellipseIn: hr(0.24, 0.564, 0.12, 0.072)), Color(hex: "#E4453A").opacity(0.26))
            overlay(Path(ellipseIn: hr(0.64, 0.564, 0.12, 0.072)), Color(hex: "#E4453A").opacity(0.26))
            overlay(Path(ellipseIn: hr(0.31, 0.41, 0.14, 0.14)), outline)
            overlay(Path(ellipseIn: hr(0.55, 0.41, 0.14, 0.14)), outline)
            overlay(Path(ellipseIn: hr(0.336, 0.376, 0.052, 0.052)), Color.white)
            overlay(Path(ellipseIn: hr(0.576, 0.376, 0.052, 0.052)), Color.white)
            context.stroke(custom { path in
                path.move(to: hp(0.42, 0.62))
                path.addQuadCurve(to: hp(0.58, 0.62), control: hp(0.50, 0.70))
            }, with: .color(outline), lineWidth: line * 0.75)

            // MARK: Hair (3 styles, rescaled onto this head)
            switch hairStyle {
            case 0:
                fill(custom { path in
                    path.move(to: hp(0.14, 0.48))
                    path.addQuadCurve(to: hp(0.50, 0.10), control: hp(0.14, 0.10))
                    path.addQuadCurve(to: hp(0.86, 0.48), control: hp(0.86, 0.10))
                    path.addQuadCurve(to: hp(0.50, 0.32), control: hp(0.78, 0.32))
                    path.addQuadCurve(to: hp(0.14, 0.48), control: hp(0.22, 0.32))
                    path.closeSubpath()
                }, hair)
            case 1:
                fill(custom { path in
                    path.move(to: hp(0.12, 0.52))
                    path.addQuadCurve(to: hp(0.50, 0.08), control: hp(0.12, 0.08))
                    path.addQuadCurve(to: hp(0.88, 0.52), control: hp(0.88, 0.08))
                    path.addQuadCurve(to: hp(0.82, 0.68), control: hp(0.88, 0.68))
                    path.addQuadCurve(to: hp(0.76, 0.34), control: hp(0.82, 0.42))
                    path.addQuadCurve(to: hp(0.50, 0.42), control: hp(0.64, 0.42))
                    path.addQuadCurve(to: hp(0.24, 0.34), control: hp(0.36, 0.42))
                    path.addQuadCurve(to: hp(0.18, 0.68), control: hp(0.18, 0.42))
                    path.addQuadCurve(to: hp(0.12, 0.52), control: hp(0.12, 0.68))
                    path.closeSubpath()
                }, hair)
            default:
                fill(Path(ellipseIn: hr(0.37, -0.01, 0.26, 0.26)), hair)
                fill(custom { path in
                    path.move(to: hp(0.16, 0.46))
                    path.addQuadCurve(to: hp(0.50, 0.14), control: hp(0.16, 0.14))
                    path.addQuadCurve(to: hp(0.84, 0.46), control: hp(0.84, 0.14))
                    path.addQuadCurve(to: hp(0.50, 0.30), control: hp(0.76, 0.30))
                    path.addQuadCurve(to: hp(0.16, 0.46), control: hp(0.24, 0.30))
                    path.closeSubpath()
                }, hair)
            }

            // MARK: Hat (fixed cream color, no slot; sits on top of whichever hair is chosen)
            if hasHat {
                fill(custom { path in
                    path.move(to: hp(0.26, 0.34))
                    path.addQuadCurve(to: hp(0.16, 0.24), control: hp(0.14, 0.34))
                    path.addQuadCurve(to: hp(0.20, 0.10), control: hp(0.06, 0.16))
                    path.addQuadCurve(to: hp(0.38, 0.07), control: hp(0.26, 0.02))
                    path.addQuadCurve(to: hp(0.62, 0.07), control: hp(0.50, -0.01))
                    path.addQuadCurve(to: hp(0.80, 0.10), control: hp(0.74, 0.02))
                    path.addQuadCurve(to: hp(0.84, 0.24), control: hp(0.94, 0.16))
                    path.addQuadCurve(to: hp(0.74, 0.34), control: hp(0.86, 0.34))
                    path.closeSubpath()
                }, Self.cream)
                fill(custom { path in
                    path.move(to: hp(0.28, 0.32)); path.addLine(to: hp(0.72, 0.32))
                    path.addLine(to: hp(0.72, 0.44))
                    path.addQuadCurve(to: hp(0.68, 0.48), control: hp(0.72, 0.48))
                    path.addLine(to: hp(0.32, 0.48))
                    path.addQuadCurve(to: hp(0.28, 0.44), control: hp(0.28, 0.48))
                    path.closeSubpath()
                }, Self.cream)
                overlay(rotated(Path(ellipseIn: hr(0.22, 0.06, 0.20, 0.10)), -26, hp(0.32, 0.16).x, hp(0.32, 0.16).y),
                       Color.white.opacity(0.5))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A rarity-tiered frame for a manager portrait: ornament count escalates by tier so it reads
/// at a glance before color even registers, per the asset pack's `character-rarity-*.svg` set.
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
            let outline = Color(hex: "#2B1D14")
            let line = max(1, rect.width * 0.035)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            func diamond(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> Path {
                var path = Path()
                path.move(to: p(cx, cy - radius)); path.addLine(to: p(cx + radius, cy))
                path.addLine(to: p(cx, cy + radius)); path.addLine(to: p(cx - radius, cy))
                path.closeSubpath()
                return path
            }

            let disc = Path(ellipseIn: rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02))
            context.fill(disc, with: .color(Theme.panel))
            context.stroke(disc, with: .color(outline), lineWidth: line)
            let ring = Path(ellipseIn: rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02))
            context.stroke(ring, with: .color(ringColor), lineWidth: rect.width * 0.05)

            if rarity >= .rare {
                let inner = Path(ellipseIn: rect.insetBy(dx: rect.width * 0.17, dy: rect.height * 0.17))
                context.stroke(inner, with: .color(ringColor.opacity(0.7)), lineWidth: rect.width * 0.026)
            }
            if rarity >= .epic {
                for (cx, cy) in [(0.22, 0.22), (0.78, 0.22), (0.22, 0.78), (0.78, 0.78)] {
                    context.fill(diamond(cx, cy, rect.width * 0.044), with: .color(ringColor))
                }
            }
            if rarity == .legendary {
                for (cx, cy) in [(0.06, 0.5), (0.94, 0.5), (0.5, 0.94)] {
                    context.fill(diamond(cx, cy, rect.width * 0.08), with: .color(ringColor))
                }
                var crest = Path()
                crest.move(to: p(0.34, 0.12)); crest.addLine(to: p(0.42, 0.20))
                crest.addLine(to: p(0.50, 0.02)); crest.addLine(to: p(0.58, 0.20))
                crest.addLine(to: p(0.66, 0.12)); crest.addLine(to: p(0.64, 0.24))
                crest.addLine(to: p(0.36, 0.24)); crest.closeSubpath()
                context.fill(crest, with: .color(ringColor))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Deterministic small-range RNG. Same seed always yields the same customer, which keeps a
/// queue stable across re-renders.
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
