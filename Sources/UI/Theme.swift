import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Per-venue look. Each venue gets its own room so travelling between them reads as
/// genuine progress rather than a reskinned list.
struct VenuePalette {
    let wallTop: Color
    let wallBottom: Color
    let floor: Color
    let counter: Color
    let counterEdge: Color
    let accent: Color
    let sign: Color

    /// Cosmetic skins are purely visual - coin-priced, never gem or power, so they can't cut
    /// against the "never sell power" line the rest of the shop holds to.
    static let skinIDs = ["classic", "neon"]

    static func of(_ theme: VenueTheme, skin: String = "classic") -> VenuePalette {
        skin == "neon" ? neon(theme) : classic(theme)
    }

    private static func classic(_ theme: VenueTheme) -> VenuePalette {
        switch theme {
        case .burger:
            return VenuePalette(wallTop: Color(hex: "#2B4E6B"), wallBottom: Color(hex: "#1B3348"),
                                floor: Color(hex: "#D9BE96"), counter: Color(hex: "#E4453A"),
                                counterEdge: Color(hex: "#A62F27"), accent: Color(hex: "#F5C242"),
                                sign: Color(hex: "#FFE9A8"))
        case .sushi:
            return VenuePalette(wallTop: Color(hex: "#2F4A46"), wallBottom: Color(hex: "#1A2F2C"),
                                floor: Color(hex: "#C9AE86"), counter: Color(hex: "#3F6B5C"),
                                counterEdge: Color(hex: "#27493E"), accent: Color(hex: "#F4A9A0"),
                                sign: Color(hex: "#F6E7C9"))
        case .pizza:
            return VenuePalette(wallTop: Color(hex: "#3A2E4C"), wallBottom: Color(hex: "#241C31"),
                                floor: Color(hex: "#CBB59A"), counter: Color(hex: "#C4462F"),
                                counterEdge: Color(hex: "#8C2E1F"), accent: Color(hex: "#F0C24B"),
                                sign: Color(hex: "#FFE6B8"))
        case .taco:
            return VenuePalette(wallTop: Color(hex: "#2C5E56"), wallBottom: Color(hex: "#173B36"),
                                floor: Color(hex: "#E0C08A"), counter: Color(hex: "#E07A3C"),
                                counterEdge: Color(hex: "#A9532A"), accent: Color(hex: "#F5D547"),
                                sign: Color(hex: "#FFF0C2"))
        case .dessert:
            return VenuePalette(wallTop: Color(hex: "#4B3355"), wallBottom: Color(hex: "#2C1E36"),
                                floor: Color(hex: "#E8D3C4"), counter: Color(hex: "#E88AA8"),
                                counterEdge: Color(hex: "#B45E7C"), accent: Color(hex: "#9BD4C8"),
                                sign: Color(hex: "#FFE7F0"))
        case .diner:
            return VenuePalette(wallTop: Color(hex: "#1E2A4A"), wallBottom: Color(hex: "#101830"),
                                floor: Color(hex: "#C9C2B8"), counter: Color(hex: "#5B8BD9"),
                                counterEdge: Color(hex: "#33528C"), accent: Color(hex: "#F26D9C"),
                                sign: Color(hex: "#D8E6FF"))
        case .foodtruck:
            return VenuePalette(wallTop: Color(hex: "#6B3A2A"), wallBottom: Color(hex: "#42200F"),
                                floor: Color(hex: "#B8B0A4"), counter: Color(hex: "#E07A3C"),
                                counterEdge: Color(hex: "#A9532A"), accent: Color(hex: "#5BD6E8"),
                                sign: Color(hex: "#FFEFD1"))
        }
    }

    /// A punchier, more saturated recolor of each room - same hue family as the classic skin
    /// so a venue stays recognizable by color, just turned up.
    private static func neon(_ theme: VenueTheme) -> VenuePalette {
        switch theme {
        case .burger:
            return VenuePalette(wallTop: Color(hex: "#3D2A6B"), wallBottom: Color(hex: "#241847"),
                                floor: Color(hex: "#F2D9A6"), counter: Color(hex: "#FF3B6B"),
                                counterEdge: Color(hex: "#B3123F"), accent: Color(hex: "#3BFFD1"),
                                sign: Color(hex: "#FFF3B0"))
        case .sushi:
            return VenuePalette(wallTop: Color(hex: "#1B4A52"), wallBottom: Color(hex: "#0D2B30"),
                                floor: Color(hex: "#E8D9B8"), counter: Color(hex: "#00C2A8"),
                                counterEdge: Color(hex: "#00786A"), accent: Color(hex: "#FF6FA5"),
                                sign: Color(hex: "#EFFFF6"))
        case .pizza:
            return VenuePalette(wallTop: Color(hex: "#4A1E5C"), wallBottom: Color(hex: "#2A0F38"),
                                floor: Color(hex: "#E8D2B0"), counter: Color(hex: "#FF4747"),
                                counterEdge: Color(hex: "#A31D1D"), accent: Color(hex: "#FFD23B"),
                                sign: Color(hex: "#FFF0C2"))
        case .taco:
            return VenuePalette(wallTop: Color(hex: "#0F5C52"), wallBottom: Color(hex: "#083631"),
                                floor: Color(hex: "#F0D9A0"), counter: Color(hex: "#FF7A29"),
                                counterEdge: Color(hex: "#B34C0F"), accent: Color(hex: "#3BFF8F"),
                                sign: Color(hex: "#FFF5D1"))
        case .dessert:
            return VenuePalette(wallTop: Color(hex: "#5C2A6B"), wallBottom: Color(hex: "#37173F"),
                                floor: Color(hex: "#F5E0EC"), counter: Color(hex: "#FF5FA0"),
                                counterEdge: Color(hex: "#C22E70"), accent: Color(hex: "#5FE8D8"),
                                sign: Color(hex: "#FFEAF5"))
        case .diner:
            return VenuePalette(wallTop: Color(hex: "#141F42"), wallBottom: Color(hex: "#0A0F24"),
                                floor: Color(hex: "#D8D2C8"), counter: Color(hex: "#3B9CFF"),
                                counterEdge: Color(hex: "#1F5CB0"), accent: Color(hex: "#FF4F94"),
                                sign: Color(hex: "#E6F0FF"))
        case .foodtruck:
            return VenuePalette(wallTop: Color(hex: "#803A18"), wallBottom: Color(hex: "#4A1E08"),
                                floor: Color(hex: "#CFC5B4"), counter: Color(hex: "#FF8A2B"),
                                counterEdge: Color(hex: "#C25512"), accent: Color(hex: "#3BFFD1"),
                                sign: Color(hex: "#FFF5DC"))
        }
    }
}

enum Theme {
    /// The outline every piece of drawn art strokes itself with - sprites, venue props, signs,
    /// rarity frames. It was previously redeclared as a local `let` in four separate Canvas
    /// closures; it is one constant because it is one decision.
    static let outline = Color(hex: "#2B1D14")

    // Shared chrome, consistent across every venue so the HUD never feels like it moved.
    static let ink = Color(hex: "#1C1622")
    static let panel = Color(hex: "#241D2E")
    static let panelRaised = Color(hex: "#332A40")
    static let stroke = Color(hex: "#4A3E59")
    static let text = Color(hex: "#F6F1EA")
    static let textDim = Color(hex: "#B3A8C0")

    static let coin = Color(hex: "#F5C242")
    static let coinDeep = Color(hex: "#D89A22")
    static let gem = Color(hex: "#5BD6E8")
    static let gemDeep = Color(hex: "#2A9DB5")
    static let star = Color(hex: "#FFD75E")
    static let positive = Color(hex: "#5DD08A")
    static let negative = Color(hex: "#E4453A")
    static let locked = Color(hex: "#6E627D")

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func body(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func numeric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded).monospacedDigit()
    }

    // MARK: Depth tokens (visual-refresh foundation)
    //
    // The old look was honest flat vector but read as unfinished: single-tone fills, hard
    // offset shadows, no light direction. These three tokens give every surface the same
    // subtle top-light without any view doing its own color math - consumed by
    // PanelBackground and ChunkyButtonStyle below, so the whole app lifts at once.

    /// A soft top-light wash layered OVER any base fill - lighter at the top, vanishing by
    /// the middle. Works on every hue, which is why it's an overlay rather than computed
    /// lighter/darker variants of each color.
    static let topLight = LinearGradient(
        stops: [.init(color: .white.opacity(0.10), location: 0),
                .init(color: .white.opacity(0.02), location: 0.45),
                .init(color: .clear, location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// Same idea for interactive fills - a touch stronger so buttons read as raised.
    static let buttonLight = LinearGradient(
        stops: [.init(color: .white.opacity(0.18), location: 0),
                .init(color: .white.opacity(0.04), location: 0.5),
                .init(color: .black.opacity(0.06), location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// Panel edge treatment: a brighter top edge fading into the ordinary stroke, which is
    /// what sells "lit from above" at a glance.
    static let edgeLight = LinearGradient(
        stops: [.init(color: Color.white.opacity(0.22), location: 0),
                .init(color: Theme.stroke, location: 0.35),
                .init(color: Theme.stroke.opacity(0.6), location: 1)],
        startPoint: .top, endPoint: .bottom)
}

// MARK: - Reusable chrome

struct PanelBackground: ViewModifier {
    var color: Color = Theme.panel
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .overlay(
                        // Top-light wash + lit top edge - the whole depth story in two
                        // overlays, shared by every panel in the game.
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.topLight)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.edgeLight, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            )
    }
}

extension View {
    func panel(_ color: Color = Theme.panel, radius: CGFloat = 18) -> some View {
        modifier(PanelBackground(color: color, radius: radius))
    }
}

/// Chunky arcade-style button. Presses translate downward onto their own shadow, which is
/// most of what makes a tap feel physical.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color
    var shadow: Color
    var disabled: Bool = false
    var radius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !disabled
        return configuration.label
            .foregroundStyle(disabled ? Theme.textDim : Theme.text)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(disabled ? Theme.locked.opacity(0.5) : shadow)
                        .offset(y: 4)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(disabled ? Theme.locked.opacity(0.75) : fill)
                        .overlay(
                            // Raised-surface light: stronger than a panel's, and it
                            // flattens while pressed so the push reads in the shading,
                            // not just the translation.
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Theme.buttonLight)
                                .opacity(disabled ? 0.3 : (pressed ? 0.35 : 1))
                        )
                }
            )
            .offset(y: pressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

enum Haptics {
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func thud() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
