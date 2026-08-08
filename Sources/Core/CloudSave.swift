import Foundation

/// Cross-device save sync on iCloud key-value storage.
///
/// KVS rather than a full CloudKit database on purpose: the save is a single JSON blob of a
/// few kilobytes, well inside the 1MB KVS budget, and KVS syncs itself without a schema, a
/// container to provision, or a record-merge layer to maintain. If the save ever grows into
/// something that needs partial updates or history, that is the point to move to CloudKit.
///
/// This needs the iCloud key-value entitlement and a signed-in iCloud account. Without
/// either, every call here fails softly and the game carries on entirely on local storage —
/// nothing about the local save depends on this working.
@MainActor
final class CloudSaveService: ObservableObject {

    static let key = "savegame.v2"

    enum Status: Equatable {
        case unavailable          // no entitlement or no iCloud account
        case idle
        case synced(Date)

        var label: String {
            switch self {
            case .unavailable: return "Unavailable"
            case .idle: return "On"
            case .synced: return "On"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    /// A remote save that is further along than the local one, waiting on the player's call.
    @Published var conflict: GameState?

    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.remoteDidChange() }
        }
        status = store.synchronize() ? .idle : .unavailable
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isAvailable: Bool { status != .unavailable }

    // MARK: Push / pull

    @discardableResult
    func push(_ state: GameState) -> Bool {
        guard isAvailable, let data = try? encoder.encode(state) else { return false }
        store.set(data, forKey: Self.key)
        guard store.synchronize() else { return false }
        status = .synced(Date())
        return true
    }

    func pull() -> GameState? {
        guard isAvailable, let data = store.data(forKey: Self.key) else { return nil }
        guard var remote = try? decoder.decode(GameState.self, from: data) else { return nil }
        remote.reconcileWithCatalog()
        return remote
    }

    /// Which save to trust. Lifetime earnings only ever go up, so it is the one field that
    /// reliably says which device has seen more of the game - unlike a timestamp, which a
    /// device with a wrong clock can win with nothing to show for it.
    nonisolated static func isAhead(_ candidate: GameState, of current: GameState) -> Bool {
        if candidate.lifetimeStars != current.lifetimeStars {
            return candidate.lifetimeStars > current.lifetimeStars
        }
        return candidate.lifetimeEarnings > current.lifetimeEarnings
    }

    /// Called on launch. A brand new local save adopts the cloud silently — that is the
    /// reinstall case and there is nothing to lose. Anything else asks first, because
    /// overwriting a played save without consent is unforgivable.
    func reconcileOnLaunch(local: GameState) -> GameState? {
        guard let remote = pull(), Self.isAhead(remote, of: local) else { return nil }

        let localIsUntouched = local.lifetimeEarnings == 0 && local.lifetimeStars == 0
        if localIsUntouched { return remote }

        conflict = remote
        return nil
    }

    private func remoteDidChange() {
        status = .synced(Date())
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
