import SwiftUI

/// A procedurally varied little person. One seed drives skin, hair, outfit, and hat so a
/// queue of customers looks like a crowd instead of a row of clones.
struct CustomerSprite: View {
    let seed: Int

    private static let skins = ["#F2C49B", "#D9A06B", "#A9714B", "#7A4E33", "#F7D9BE", "#5C3A24"]
    private static let hairs = ["#2E2A2B", "#5B3A20", "#C8873B", "#8E4A3C", "#3C4A6B", "#B8B2AD"]
    private static let shirts = ["#4C79C0", "#D4685A", "#57A773", "#C9A227", "#8367C7", "#3FA8A0", "#E08A50"]
    private static let pants = ["#37405C", "#2E3A2F", "#4A3A52", "#5C4632"]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let line = max(1, rect.width * 0.04)
            let outline = Color.black.opacity(0.3)

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                       width: w * rect.width, height: h * rect.height)
            }
            func fill(_ path: Path, _ color: Color, stroked: Bool = true) {
                context.fill(path, with: .color(color))
                if stroked { context.stroke(path, with: .color(outline), lineWidth: line) }
            }
            func capsule(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                Path(roundedRect: r(x, y, w, h), cornerRadius: radius * rect.width)
            }

            let rng = SeededRandom(seed: seed)
            let skin = Color(hex: Self.skins[rng.next(Self.skins.count)])
            let hair = Color(hex: Self.hairs[rng.next(Self.hairs.count)])
            let shirt = Color(hex: Self.shirts[rng.next(Self.shirts.count)])
            let trouser = Color(hex: Self.pants[rng.next(Self.pants.count)])
            let hasHat = rng.next(4) == 0
            let heightJitter = CGFloat(rng.next(3)) * 0.03

            let top = 0.06 + heightJitter

            // Legs, then torso, then arms, then head - back to front.
            fill(capsule(0.34, 0.74, 0.11, 0.24, 0.05), trouser)
            fill(capsule(0.55, 0.74, 0.11, 0.24, 0.05), trouser)
            fill(capsule(0.28, 0.44, 0.44, 0.34, 0.1), shirt)
            fill(capsule(0.19, 0.47, 0.11, 0.26, 0.05), shirt)
            fill(capsule(0.7, 0.47, 0.11, 0.26, 0.05), shirt)
            fill(Path(ellipseIn: r(0.19, 0.68, 0.12, 0.12)), skin)
            fill(Path(ellipseIn: r(0.69, 0.68, 0.12, 0.12)), skin)

            fill(Path(ellipseIn: r(0.27, top, 0.46, 0.42)), skin)

            var hairPath = Path()
            hairPath.move(to: p(0.27, top + 0.2))
            hairPath.addQuadCurve(to: p(0.73, top + 0.2), control: p(0.5, top - 0.09))
            hairPath.closeSubpath()
            fill(hairPath, hair)

            if hasHat {
                fill(capsule(0.22, top + 0.04, 0.56, 0.06, 0.03), shirt)
                fill(capsule(0.32, top - 0.08, 0.36, 0.14, 0.05), shirt)
            }

            // Face: two dots and a smile is all it takes to read as happy.
            context.fill(Path(ellipseIn: r(0.38, top + 0.19, 0.07, 0.08)), with: .color(.black.opacity(0.75)))
            context.fill(Path(ellipseIn: r(0.55, top + 0.19, 0.07, 0.08)), with: .color(.black.opacity(0.75)))
            var smile = Path()
            smile.move(to: p(0.4, top + 0.31))
            smile.addQuadCurve(to: p(0.6, top + 0.31), control: p(0.5, top + 0.38))
            context.stroke(smile, with: .color(.black.opacity(0.6)), lineWidth: line)
        }
        .drawingGroup()
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
