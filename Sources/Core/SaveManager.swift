import Foundation

/// Where a `GameEngine` reads and writes its state. Injecting this keeps tests - which run
/// inside the app as their test host - from trampling the player's real save file.
protocol GamePersisting {
    func load() -> GameState
    func save(_ state: GameState)
    func wipe()
}

struct DiskPersistence: GamePersisting {
    func load() -> GameState { SaveManager.load() }
    func save(_ state: GameState) { SaveManager.save(state) }
    func wipe() { SaveManager.wipe() }
}

/// Reads a fresh game and throws writes away. Used by tests and SwiftUI previews.
struct EphemeralPersistence: GamePersisting {
    func load() -> GameState { GameState.newGame() }
    func save(_ state: GameState) {}
    func wipe() {}
}

/// Disk persistence for the save file. Writes are atomic so a crash mid-save can never
/// leave the player with a half-written file and a wiped empire.
enum SaveManager {

    static let filename = "savegame.json"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("FoodCourtTycoon", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var fileURL: URL { directory.appendingPathComponent(filename) }

    static func load() -> GameState {
        guard let data = try? Data(contentsOf: fileURL) else {
            return GameState.newGame()
        }
        do {
            var state = try decoder.decode(GameState.self, from: data)
            state = migrate(state)
            state.reconcileWithCatalog()
            return state
        } catch {
            // A corrupt save is unrecoverable, but silently wiping it would be worse than
            // keeping a copy around for diagnosis.
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return GameState.newGame()
        }
    }

    static func save(_ state: GameState) {
        guard let data = try? encoder.encode(state) else { return }
        let temp = fileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temp)
        } catch {
            // Last resort: a direct write still beats losing the session entirely.
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Room to evolve the save format without stranding existing players.
    private static func migrate(_ state: GameState) -> GameState {
        var state = state
        if state.schemaVersion < GameState.currentSchemaVersion {
            state.schemaVersion = GameState.currentSchemaVersion
        }
        return state
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
