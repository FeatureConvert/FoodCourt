import SwiftUI

/// The room itself: back wall, sign, floor, counter, and the queue of waiting customers.
/// Purely decorative, but it is what makes the numbers feel like a restaurant.
struct VenueStageView: View {
    @EnvironmentObject private var engine: GameEngine
    @EnvironmentObject private var sound: SoundService
    let onGolden: (Double) -> Void
    var onCustomize: (() -> Void)? = nil

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
                VenuePropsView(theme: venue.theme)
                    .frame(height: h * 0.62)
                    .frame(maxHeight: .infinity, alignment: .top)

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
                    GoldenCustomerView(seed: golden.seed) {
                        let earned = engine.collectGolden()
                        Haptics.success()
                        sound.play(.reward)
                        onGolden(earned)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, h * 0.14)
                }

                // Counter across the front.
                ZStack(alignment: .top) {
                    Rectangle().fill(palette.counterEdge)
                    Rectangle().fill(palette.counter).frame(height: 7)
                }
                .frame(height: h * 0.17)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.35), lineWidth: 2)
            )
        }
        .frame(height: 168)
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
                CustomerSprite(seed: seed)
                    .equatable()
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
