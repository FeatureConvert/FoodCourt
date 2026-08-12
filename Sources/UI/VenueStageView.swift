import SwiftUI

/// The room itself: back wall, sign, floor, counter, and the queue of waiting customers.
/// Purely decorative, but it is what makes the numbers feel like a restaurant.
struct VenueStageView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onGolden: (Double) -> Void
    var onCustomize: (() -> Void)? = nil
    /// Portrait's stage sits above a scrolling list at a fixed height; iPad landscape gives
    /// it a real column instead and passes nil so it fills whatever height that column
    /// measures out to (see RootView.landscapeContent) rather than sitting pinned to this
    /// portrait constant with empty space stranded around it.
    var fixedHeight: CGFloat? = 168

    private var venue: VenueSpec { Balance.venue(engine.state.currentVenue) }
    private var palette: VenuePalette {
        VenuePalette.of(venue.theme, skin: engine.state.skin(venue: venue.id))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .bottom) {
                LinearGradient(colors: [palette.wallTop.opacity(0.9), palette.wallBottom],
                               startPoint: .top, endPoint: .bottom)

                // Warm overhead pool of light: an elliptical wash falling from the string
                // lights toward the counter, which is what turns "a gradient wall" into
                // "a lit room". Pure vector, static, costs nothing per frame.
                RadialGradient(
                    stops: [.init(color: palette.accent.opacity(0.16), location: 0),
                            .init(color: palette.accent.opacity(0.05), location: 0.5),
                            .init(color: .clear, location: 1)],
                    center: .init(x: 0.5, y: 0.22),
                    startRadius: 0, endRadius: w * 0.75)

                // Wall dressing - stays clear of the centered sign and the queue below.
                // Rebuilt rooms draw a full layered scene instead; the rest still come through
                // the original props while the sweep works through them one at a time.
                if VenueSceneView.rebuilt.contains(venue.theme) {
                    VenueSceneView(theme: venue.theme, palette: palette, layer: .wall)
                    if VenueSceneView.hasHangingLayer.contains(venue.theme) {
                        SwayingHangingLayer(theme: venue.theme, palette: palette)
                    }
                } else {
                    VenuePropsView(theme: venue.theme)
                        .frame(height: h * 0.62)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                // Floor plane.
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(colors: [palette.floor, palette.floor.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: h * 0.42)
                        .overlay(
                            // Contact shadow where floor meets wall - grounds the plane.
                            LinearGradient(colors: [.black.opacity(0.22), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 14),
                            alignment: .top)
                }

                // Floor material sits over the plane, in the same coordinate space as the wall
                // layer above - which is why the two can be split across the floor gradient.
                if VenueSceneView.rebuilt.contains(venue.theme) {
                    VenueSceneView(theme: venue.theme, palette: palette, layer: .floor)
                }

                // Soft edge vignette so the stage reads as a lit interior, not a flat card.
                RoundedRectangle(cornerRadius: 0)
                    .fill(RadialGradient(
                        stops: [.init(color: .clear, location: 0.72),
                                .init(color: .black.opacity(0.18), location: 1)],
                        center: .center, startRadius: 0, endRadius: w * 0.72))
                    .allowsHitTesting(false)

                // Hanging sign.
                VStack(spacing: 2) {
                    Text(venue.name.uppercased())
                        .font(Theme.title(15))
                        .foregroundStyle(Color(hex: "#2B1D14"))
                    Text(venue.tagline)
                        .font(Theme.body(10, weight: .medium))
                        .foregroundStyle(Color(hex: "#2B1D14").opacity(0.65))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(VenueSignFrame(plate: palette.sign))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
                .contentShape(Rectangle())
                .onTapGesture { onCustomize?() }

                CustomerQueueView(width: w)
                    .frame(height: h * 0.46)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, h * 0.16)

                // The VIP stands centre-stage. Anywhere trailing would put the tap target
                // under the boost and rush buttons, which sit in that corner.
                if let golden = engine.golden {
                    GoldenCustomerView(seed: golden.seed, isCritic: golden.isCritic) {
                        let earned = engine.collectGolden()
                        Haptics.success()
                        sound.play(.reward)
                        onGolden(earned)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, h * 0.14)
                }

                // Counter across the front. The hairline highlight along the very top edge is
                // what makes it read as a solid lit surface rather than a flat coloured band.
                ZStack(alignment: .top) {
                    Rectangle().fill(palette.counterEdge)
                    Rectangle().fill(palette.counter).frame(height: 7)
                    Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1.5)
                    if VenueSceneView.rebuilt.contains(venue.theme) {
                        VenueSceneView(theme: venue.theme, palette: palette, layer: .counterFront)
                    }
                }
                .frame(height: h * 0.17)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.35), lineWidth: 2)
            )
        }
        .frame(height: fixedHeight)
    }
}

/// Customers file in on the left and are retired as stations complete cycles.
struct CustomerQueueView: View {
    @EnvironmentObject private var engine: GameEngine
    let width: CGFloat

    @State private var seeds: [Int] = []
    @State private var nextSeed = 1
    @State private var lastRotation = Date.distantPast

    private var capacity: Int { max(3, min(6, Int(width / 58))) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(seeds, id: \.self) { seed in
                BobbingSprite(seed: seed)
                    .frame(width: 44, height: 62)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.6).combined(with: .opacity)
                    ))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .onAppear(perform: refill)
        .onChange(of: engine.servedCustomers) { _, _ in rotate() }
        .onChange(of: engine.state.currentVenue) { _, _ in
            seeds.removeAll()
            refill()
        }
    }

    private func refill() {
        while seeds.count < capacity {
            seeds.append(nextSeed)
            nextSeed += 1
        }
    }

    private func rotate() {
        // A maxed venue completes dozens of cycles a second; animating each one would be
        // visual noise and a waste of frames.
        let now = Date()
        guard now.timeIntervalSince(lastRotation) > 0.35 else { return }
        lastRotation = now

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            if !seeds.isEmpty { seeds.removeFirst() }
            seeds.append(nextSeed)
            nextSeed += 1
        }
        // Each rotation is a chance for a VIP to walk in.
        engine.rollGoldenCustomer()
        // ...and a separate chance for a specific station to get an order.
        engine.rollStationOrder()
    }
}

/// A queued customer with a slow idle bob - design spec: +/-2.6 units of the 150-unit rig
/// frame, 2.9s ease-in-out, phase-offset per figure. The offset is a plain `.offset(y:)` on an
/// otherwise-unchanged `.equatable()` sprite, so the only per-frame cost is repositioning an
/// already-rendered layer, not redrawing the figure - and it's confined to this one small
/// view, not the wall/floor scene around it.
/// Sways the hanging décor layer (garland/lantern/flag/pendant) as one rigid piece around its
/// top edge - a physical wire or cord swinging, not each bulb moving independently. `±1°`,
/// design's own number (see the retired comment on `warmGarland`'s old call site); the 5.5s
/// period isn't otherwise documented and is this pass's own choice - slower than the 2.5-2.9s
/// bob/ring cadences elsewhere, since a slack wire of bulbs reads as heavier than a customer or
/// a rarity ring. Same capped 30fps clock and reduce-motion parking as the rest of the pass;
/// rotating the whole pre-rendered Canvas is one GPU-composited transform, not a redraw, so this
/// costs about the same as `.wall` itself already did.
private struct SwayingHangingLayer: View {
    let theme: VenueTheme
    let palette: VenuePalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            VenueSceneView(theme: theme, palette: palette, layer: .hangingLayer)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let angle = sin(t / 5.5 * 2 * .pi) * 1.0
                VenueSceneView(theme: theme, palette: palette, layer: .hangingLayer)
                    .rotationEffect(.degrees(angle), anchor: .top)
            }
        }
    }
}

private struct BobbingSprite: View {
    let seed: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            CustomerSprite(seed: seed).equatable()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                // Deterministic per-seed phase, not random per-frame, so a given customer's
                // bob doesn't visibly jump when the view re-renders.
                let phase = Double(seed % 29) / 29.0 * 2.9
                let t = timeline.date.timeIntervalSinceReferenceDate
                let bob = sin((t + phase) / 2.9 * 2 * .pi) * (2.6 / 150.0) * 62
                CustomerSprite(seed: seed).equatable()
                    .offset(y: bob)
            }
        }
    }
}
