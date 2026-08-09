import SwiftUI

/// Decorative wall/counter dressing, one set per venue theme, layered behind the hanging
/// sign and above the wall gradient. Transcribed from the asset pack's `venue-*-props.svg`
/// set - each file carries its own venue's hex directly rather than a recolorable slot (per
/// the pack's own README: "venue prop sets carry their venue's hex directly, since there is
/// one file per venue"), so unlike food/UI icons these are not palette-driven.
///
/// The source assets assume a roughly square 100x100 box; this game's stage strip is short
/// and wide, so positions are placed independently on each axis (allowed to spread with the
/// available width) while stroke widths and true circles are sized off `unit`, the *smaller*
/// of the two axes - otherwise a thin garland string or a round light bulb stretches into a
/// thick ribbon or a flat ellipse the moment the frame isn't square.
struct VenuePropsView: View {
    let theme: VenueTheme

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let outline = Color(hex: "#2B1D14")
            let unit = min(rect.width, rect.height) / 100
            let line = unit * 3

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
            }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                let c = p(cx, cy), radius = r * unit
                return Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                              width: radius * 2, height: radius * 2))
            }
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: p(x, y).x, y: p(x, y).y,
                                         width: w / 100 * rect.width, height: h / 100 * rect.height),
                    cornerRadius: radius * unit)
            }
            func custom(_ build: (inout Path) -> Void) -> Path {
                var path = Path(); build(&path); return path
            }
            func fill(_ path: Path, _ color: Color, stroked: Bool = true) {
                context.fill(path, with: .color(color))
                if stroked { context.stroke(path, with: .color(outline), lineWidth: line) }
            }
            func overlay(_ path: Path, _ color: Color) { context.fill(path, with: .color(color)) }
            func dot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color, stroked: Bool = true) {
                fill(circle(cx, cy, r), color, stroked: stroked)
            }
            /// A bulb that actually glows: two translucent halos behind the lit dot - fake
            /// bloom, three fills, no filters, so it stays free at render time.
            func glowDot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color) {
                context.fill(circle(cx, cy, r * 2.6), with: .color(color.opacity(0.14)))
                context.fill(circle(cx, cy, r * 1.7), with: .color(color.opacity(0.26)))
                dot(cx, cy, r, color)
            }
            func openStroke(_ color: Color, width: CGFloat, opacity: Double = 1,
                            _ build: (inout Path) -> Void) {
                context.stroke(custom(build), with: .color(color.opacity(opacity)), lineWidth: width)
            }

            switch theme {

            case .burger:
                openStroke(outline, width: line) { path in
                    path.move(to: p(2, 10))
                    path.addQuadCurve(to: p(50, 16), control: p(26, 28))
                    path.addQuadCurve(to: p(98, 10), control: p(74, 28))
                }
                let burgerLights: [(CGFloat, CGFloat, String)] = [
                    (16, 20, "#F5C242"), (32, 25, "#FFE9A8"), (50, 20, "#E4453A"),
                    (68, 25, "#F5C242"), (84, 20, "#FFE9A8"),
                ]
                for (cx, cy, hex) in burgerLights {
                    glowDot(cx, cy, 4.6, Color(hex: hex))
                }
                fill(rr(60, 40, 36, 44, 4), Color(hex: "#3A3346"))
                fill(rr(65, 45, 26, 34, 2), Color(hex: "#2E2A2B"))
                for y: CGFloat in [53, 61, 69] {
                    openStroke(Color(hex: "#F6E7C9"), width: unit * 2.4, opacity: 0.8) { path in
                        path.move(to: p(69, y)); path.addLine(to: p(y == 61 ? 83 : 86, y))
                    }
                }
                overlay(custom { path in
                    path.move(to: p(88, 42)); path.addLine(to: p(96, 42))
                    path.addLine(to: p(96, 84)); path.addLine(to: p(88, 84)); path.closeSubpath()
                }, outline.opacity(0.16))

            case .sushi:
                fill(rr(4, 28, 40, 58, 3), Color(hex: "#C9AE86"))
                for x: CGFloat in [14, 24, 34] {
                    openStroke(outline, width: unit * 2.4, opacity: 0.4) { path in
                        path.move(to: p(x, 30)); path.addLine(to: p(x, 84))
                    }
                }
                overlay(custom { path in
                    path.move(to: p(4, 28)); path.addLine(to: p(14, 28))
                    path.addLine(to: p(14, 86)); path.addLine(to: p(4, 86)); path.closeSubpath()
                }, Color.white.opacity(0.14))
                openStroke(outline, width: unit * 2.4) { path in
                    path.move(to: p(64, 4)); path.addLine(to: p(64, 16))
                }
                openStroke(outline, width: unit * 2.4) { path in
                    path.move(to: p(86, 4)); path.addLine(to: p(86, 12))
                }
                dot(64, 30, 12, Color(hex: "#E4453A"))
                dot(86, 24, 9, Color(hex: "#F4A9A0"))
                fill(rr(58, 14, 12, 4, 1.6), Color(hex: "#3A3346"))
                fill(rr(80, 12, 12, 4, 1.6), Color(hex: "#3A3346"))
                overlay(circle(59, 23, 4), Color.white.opacity(0.28))

            case .pizza:
                openStroke(outline, width: line) { path in
                    path.move(to: p(2, 8))
                    path.addQuadCurve(to: p(50, 14), control: p(26, 26))
                    path.addQuadCurve(to: p(98, 8), control: p(74, 26))
                }
                let pizzaLights: [(CGFloat, CGFloat, String)] = [
                    (20, 19, "#F0C24B"), (38, 23, "#FFE6B8"), (62, 23, "#F0C24B"), (80, 19, "#FFE6B8"),
                ]
                for (cx, cy, hex) in pizzaLights {
                    glowDot(cx, cy, 4.4, Color(hex: hex))
                }
                openStroke(outline, width: unit * 2.4) { path in
                    path.move(to: p(16, 34)); path.addLine(to: p(16, 44))
                }
                dot(12, 52, 6, Color(hex: "#F6E7C9"), stroked: false)
                dot(20, 54, 6, Color(hex: "#EDE0C4"), stroked: false)
                dot(16, 60, 6, Color(hex: "#F6E7C9"))
                openStroke(outline, width: unit * 2.4) { path in
                    path.move(to: p(84, 34)); path.addLine(to: p(84, 44))
                }
                fill(custom { path in
                    path.move(to: p(84, 44))
                    path.addQuadCurve(to: p(78, 74), control: p(72, 56))
                    path.addQuadCurve(to: p(90, 74), control: p(84, 60))
                    path.addQuadCurve(to: p(84, 44), control: p(96, 56))
                    path.closeSubpath()
                }, Color(hex: "#6E8C3A"))
                overlay(circle(10, 48, 3), Color.white.opacity(0.3))

            case .taco:
                openStroke(outline, width: line) { path in
                    path.move(to: p(2, 8)); path.addQuadCurve(to: p(98, 8), control: p(50, 26))
                }
                let tacoPennants: [(CGFloat, CGFloat, CGFloat, String)] = [
                    (10, 12, 26, "#F5D547"), (30, 17, 46, "#E07A3C"),
                    (50, 19, 66, "#5C9E4A"), (70, 15, 86, "#E4453A"),
                ]
                for (x0, y0, x1, hex) in tacoPennants {
                    let mid = (x0 + x1) / 2
                    fill(custom { path in
                        path.move(to: p(x0, y0)); path.addLine(to: p(x1, y0))
                        path.addLine(to: p(x1 - 3, y0 + 18))
                        path.addLine(to: p(mid, y0 + 13))
                        path.addLine(to: p(x0 + 3, y0 + 18))
                        path.closeSubpath()
                    }, Color(hex: hex))
                }
                fill(custom { path in
                    path.move(to: p(18, 62))
                    path.addQuadCurve(to: p(26, 44), control: p(18, 44))
                    path.addQuadCurve(to: p(34, 62), control: p(34, 44))
                    path.addQuadCurve(to: p(26, 76), control: p(34, 76))
                    path.addQuadCurve(to: p(18, 62), control: p(18, 76))
                    path.closeSubpath()
                }, Color(hex: "#5C9E4A"))
                fill(custom { path in
                    path.move(to: p(18, 56))
                    path.addQuadCurve(to: p(8, 64), control: p(8, 56))
                    path.addQuadCurve(to: p(12, 68), control: p(8, 68))
                    path.addQuadCurve(to: p(18, 60), control: p(12, 60))
                    path.closeSubpath()
                }, Color(hex: "#5C9E4A"))
                fill(custom { path in
                    path.move(to: p(34, 52))
                    path.addQuadCurve(to: p(44, 60), control: p(44, 52))
                    path.addQuadCurve(to: p(40, 64), control: p(44, 64))
                    path.addQuadCurve(to: p(34, 56), control: p(40, 56))
                    path.closeSubpath()
                }, Color(hex: "#5C9E4A"))
                fill(custom { path in
                    path.move(to: p(14, 76)); path.addLine(to: p(38, 76))
                    path.addLine(to: p(35, 92))
                    path.addQuadCurve(to: p(32, 94), control: p(35, 94))
                    path.addLine(to: p(20, 94))
                    path.addQuadCurve(to: p(17, 92), control: p(17, 94))
                    path.closeSubpath()
                }, Color(hex: "#C4462F"))
                openStroke(.white, width: unit * 3, opacity: 0.22) { path in
                    path.move(to: p(28, 46)); path.addQuadCurve(to: p(32, 64), control: p(32, 52))
                }

            default: // dessert
                openStroke(outline, width: line) { path in
                    path.move(to: p(2, 8)); path.addQuadCurve(to: p(98, 8), control: p(50, 24))
                }
                let dessertPennants: [(CGFloat, CGFloat, CGFloat, String)] = [
                    (12, 11, 26, "#E88AA8"), (32, 16, 46, "#9BD4C8"),
                    (54, 16, 68, "#FFE7F0"), (74, 11, 88, "#E88AA8"),
                ]
                for (x0, y0, x1, hex) in dessertPennants {
                    fill(custom { path in
                        path.move(to: p(x0, y0)); path.addLine(to: p(x1, y0))
                        path.addLine(to: p((x0 + x1) / 2, y0 + 15)); path.closeSubpath()
                    }, Color(hex: hex))
                }
                fill(rr(58, 80, 38, 8, 3), Color(hex: "#E8D3C4"))
                dot(68, 74, 10, Color(hex: "#E88AA8"))
                dot(68, 64, 10, Color(hex: "#9BD4C8"))
                dot(68, 54, 10, Color(hex: "#FFE7F0"))
                dot(87, 74, 8, Color(hex: "#FFE7F0"))
                dot(87, 66, 8, Color(hex: "#E88AA8"))
                overlay(circle(64, 52, 4), Color.white.opacity(0.4))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The hanging sign's plate, transcribed from `venue-sign-frame.svg`. Shared across every
/// venue and recolored via the room's own `SIGN` slot - a bespoke frame per venue would buy
/// little, since the sign reads by color and position at room scale, not its outline. Uses
/// the same axis-independent-position / `unit`-scaled-detail approach as `VenuePropsView`,
/// since the sign's own frame (wide text block) is also far from square.
struct VenueSignFrame: View {
    let plate: Color

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let outline = Color(hex: "#2B1D14")
            let hardware = Color(hex: "#3A3346")
            let unit = min(rect.width, rect.height) / 100
            let line = unit * 4

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
            }
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: p(x, y).x, y: p(x, y).y,
                                         width: w / 100 * rect.width, height: h / 100 * rect.height),
                    cornerRadius: radius * unit)
            }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                let c = p(cx, cy), radius = r * unit
                return Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                              width: radius * 2, height: radius * 2))
            }

            context.stroke(Path { path in
                path.move(to: p(30, 2)); path.addLine(to: p(34, 15))
            }, with: .color(hardware), lineWidth: line)
            context.stroke(Path { path in
                path.move(to: p(70, 2)); path.addLine(to: p(66, 15))
            }, with: .color(hardware), lineWidth: line)
            context.fill(rr(8, 0, 84, 5, 2.5), with: .color(hardware))

            let body = rr(6, 12, 88, 84, 11)
            context.fill(body, with: .color(plate))
            context.stroke(body, with: .color(outline), lineWidth: line)

            context.fill(rr(14, 20, 72, 68, 6), with: .color(outline.opacity(0.10)))
            context.fill(Path { path in
                path.move(to: p(14, 20)); path.addLine(to: p(86, 20))
                path.addLine(to: p(86, 32))
                path.addQuadCurve(to: p(14, 32), control: p(50, 42))
                path.closeSubpath()
            }, with: .color(.white.opacity(0.26)))
            context.fill(Path { path in
                path.move(to: p(80, 14)); path.addLine(to: p(94, 14))
                path.addLine(to: p(94, 92)); path.addLine(to: p(80, 92)); path.closeSubpath()
            }, with: .color(outline.opacity(0.10)))

            context.fill(circle(30, 15, 2.6), with: .color(hardware))
            context.fill(circle(70, 15, 2.6), with: .color(hardware))
        }
        .accessibilityHidden(true)
    }
}
