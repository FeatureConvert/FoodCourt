import SwiftUI

@main
struct FableApp: App {
    @StateObject private var engine = GameEngine()
    @StateObject private var store = StoreService()
    @StateObject private var cloud = CloudSaveService()
    @StateObject private var notifications = NotificationService()
    @StateObject private var gameCenter = GameCenterService()
    @StateObject private var sound = SoundService()

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(engine)
                    .environmentObject(store)
                    .environmentObject(cloud)
                    .environmentObject(notifications)
                    .environmentObject(gameCenter)
                    .environmentObject(sound)

                if !isReady {
                    SplashView()
                }
            }
            .task {
                let startedAt = Date()
                // The store needs the engine to grant rewards, and the engine is only
                // available once both objects exist.
                store.attach(engine: engine)
                engine.attachCloud(cloud)
                // A reinstall adopts the cloud save silently; a played save asks first.
                if let remote = cloud.reconcileOnLaunch(local: engine.state) {
                    engine.adoptCloudSave(remote)
                }
                await store.loadProducts()
                await store.refreshEntitlements()
                engine.handleForeground()
                gameCenter.authenticate()

                // Hold the splash up for a minimum stretch so the branding always reads as a
                // deliberate beat rather than a flash that only shows up on a slow connection.
                let elapsed = Date().timeIntervalSince(startedAt)
                let minimumDisplay = 0.6
                if elapsed < minimumDisplay {
                    try? await Task.sleep(nanoseconds: UInt64((minimumDisplay - elapsed) * 1_000_000_000))
                }
                withAnimation(.easeInOut(duration: 0.3)) { isReady = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                engine.start()
                engine.handleForeground()
                notifications.cancelAll()
            case .inactive, .background:
                engine.handleBackground()
                engine.stop()
                if notificationsEnabled { notifications.reschedule(for: engine.state) }
            @unknown default:
                break
            }
        }
    }
}
