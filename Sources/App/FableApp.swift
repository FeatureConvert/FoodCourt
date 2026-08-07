import SwiftUI

@main
struct FableApp: App {
    @StateObject private var engine = GameEngine()
    @StateObject private var store = StoreService()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(store)
                .task {
                    // The store needs the engine to grant rewards, and the engine is only
                    // available once both objects exist.
                    store.attach(engine: engine)
                    await store.loadProducts()
                    await store.refreshEntitlements()
                    engine.handleForeground()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                engine.start()
                engine.handleForeground()
            case .inactive, .background:
                engine.handleBackground()
                engine.stop()
            @unknown default:
                break
            }
        }
    }
}
