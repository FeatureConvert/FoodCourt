import SwiftUI

/// Debug-only comparison switch for the station card/button depth treatment - lets the
/// shipped soft top-light system (`PanelBackground`/`ChunkyButtonStyle` in Theme.swift), a
/// bordered variant of it, and a fully flat hard-shadow variant sit side by side on a real
/// screen before either replaces the shared components for everyone. Defaults to `.current`,
/// so nothing changes unless the debug menu is opened and the variant switched.
enum CardStyleVariant: String, CaseIterable, Identifiable {
    case current, borderedSoft, hardShadow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .current: "Current"
        case .borderedSoft: "Bordered"
        case .hardShadow: "Hard shadow"
        }
    }
}

private struct CardStyleVariantKey: EnvironmentKey {
    static let defaultValue: CardStyleVariant = .current
}

extension EnvironmentValues {
    var cardStyleVariant: CardStyleVariant {
        get { self[CardStyleVariantKey.self] }
        set { self[CardStyleVariantKey.self] = newValue }
    }
}

extension View {
    /// Drop-in alternative to `.panel(_:radius:)` that can render any of the three card
    /// treatments under review - see `CardStyleVariant`.
    @ViewBuilder
    func stylizedPanel(_ variant: CardStyleVariant, color: Color = Theme.panel, radius: CGFloat = 18) -> some View {
        switch variant {
        case .current: self.panel(color, radius: radius)
        case .borderedSoft: self.modifier(BorderedPanelBackground(color: color, radius: radius))
        case .hardShadow: self.modifier(HardShadowPanelBackground(color: color, radius: radius))
        }
    }
}

/// "Add borders, keep soft shadow": everything `PanelBackground` already does, plus a visible
/// flat-color border - the low-risk half of the card-treatment review.
struct BorderedPanelBackground: ViewModifier {
    var color: Color = Theme.panel
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.topLight))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            )
    }
}

/// "Switch to hard offset shadow": flat fill, flat border, a hard offset shadow with no blur -
/// replaces the soft top-light system entirely instead of layering onto it, matching the
/// Kenney-UI-Pack construction technique from the reskin mockup.
struct HardShadowPanelBackground: ViewModifier {
    var color: Color = Theme.panel
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.black.opacity(0.35))
                        .offset(x: 2, y: 3)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(color)
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 2))
                }
            )
    }
}

/// `ChunkyButtonStyle` plus a visible flat-color border - the button half of "bordered, soft
/// shadow kept".
struct BorderedChunkyButtonStyle: ButtonStyle {
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
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Theme.buttonLight)
                                .opacity(disabled ? 0.3 : (pressed ? 0.35 : 1))
                        )
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1.5))
                }
            )
            .offset(y: pressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Flat fill, flat border, hard offset shadow with no blur - the button half of "switch to
/// hard offset shadow".
struct HardShadowButtonStyle: ButtonStyle {
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
                        .fill(disabled ? Theme.locked.opacity(0.4) : shadow)
                        .offset(x: 2, y: 3)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(disabled ? Theme.locked.opacity(0.75) : fill)
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1.5))
                }
            )
            .offset(y: pressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Applies whichever of the three button styles the review is currently set to, so call
/// sites need only one switch each instead of three parallel `.buttonStyle` chains.
@ViewBuilder
func styledButton<Label: View>(
    _ button: Button<Label>,
    variant: CardStyleVariant,
    fill: Color,
    shadow: Color,
    disabled: Bool = false,
    radius: CGFloat = 16
) -> some View {
    switch variant {
    case .current:
        button.buttonStyle(ChunkyButtonStyle(fill: fill, shadow: shadow, disabled: disabled, radius: radius))
    case .borderedSoft:
        button.buttonStyle(BorderedChunkyButtonStyle(fill: fill, shadow: shadow, disabled: disabled, radius: radius))
    case .hardShadow:
        button.buttonStyle(HardShadowButtonStyle(fill: fill, shadow: shadow, disabled: disabled, radius: radius))
    }
}
