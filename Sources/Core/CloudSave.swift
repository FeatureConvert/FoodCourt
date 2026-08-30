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

    /// The routine autosave path (`GameEngine.handleBackground`) - unlike `push`, this
    /// re-checks what's actually on iCloud right before writing and refuses to clobber a
    /// save that's further along than this device's, surfacing it as a conflict instead.
    ///
    /// `push` itself has to stay a plain, unconditional write: `CloudConflictView`'s "Keep
    /// this device" button calls it specifically to overwrite a remote it already knows is
    /// further along, because the player just said so - guarding `push` itself would silently
    /// defeat that explicit choice. The bug this exists to close is different: nothing ever
    /// checked before an *automatic* background push, so if this device merely fell behind
    /// (another of the player's own devices pushed while this one sat foregrounded and
    /// unaware - `remoteDidChange` only updates the status label, it doesn't compare), the
    /// next backgrounding silently overwrote the more-advanced remote save with no prompt,
    /// contradicting the promise in Settings: "the game always asks before touching this
    /// one's progress."
    @discardableResult
    func pushIfNotBehind(_ state: GameState) -> Bool {
        guard isAvailable else { return false }
        if let remote = pull(), Self.isAhead(remote, of: state) {
            conflict = remote
            return false
        }
        return push(state)
    }

    /// Clears the remote save outright - for a player who deliberately erases their progress.
    /// Without this, `reconcileOnLaunch`'s own "brand new local save adopts the cloud
    /// silently" rule would undo the erase on the very next launch or sync tick, since a
    /// freshly-wiped local save looks exactly like a first-ever install to it.
    func wipeRemote() {
        guard isAvailable else { return }
        store.removeObject(forKey: Self.key)
        store.synchronize()
    }

    func pull() -> GameState? {
        guard isAvailable, let data = store.data(forKey: Self.key) else { return nil }
        guard var remote = try? decoder.decode(GameState.self, from: data) else { return nil }
        remote.reconcileWithCatalog()
        return remote
    }

    /// Which save to trust. Progress fields that only ever go up (with one deliberate
    /// exception, below) say which device has seen more of the game - unlike a timestamp,
    /// which a device with a wrong clock can win with nothing to show for it.
    ///
    /// Ordering matters and each step exists for a failure that was real:
    /// - `legacy.level` first, because `legacyReset()` deliberately zeroes stars - compared
    ///   stars-first, the device that just performed a Legacy reset looked *behind* any
    ///   stale device that hadn't synced yet, which could clobber the reset.
    /// - `prestigeCount` and research ranks as tiebreakers, because two saves clamped by
    ///   the corruption repair in `GameState.init(from:)` tie exactly on stars AND
    ///   earnings, and without a further tiebreaker a genuinely different remote was
    ///   silently ignored.
    nonisolated static func isAhead(_ candidate: GameState, of current: GameState) -> Bool {
        if candidate.legacy.level != current.legacy.level {
            return candidate.legacy.level > current.legacy.level
        }
        if candidate.lifetimeStars != current.lifetimeStars {
            return candidate.lifetimeStars > current.lifetimeStars
        }
        if candidate.lifetimeEarnings != current.lifetimeEarnings {
            return candidate.lifetimeEarnings > current.lifetimeEarnings
        }
        if candidate.prestigeCount != current.prestigeCount {
            return candidate.prestigeCount > current.prestigeCount
        }
        let candidateRanks = candidate.research.values.reduce(0, +)
        let currentRanks = current.research.values.reduce(0, +)
        return candidateRanks > currentRanks
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
