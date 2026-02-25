import Foundation

struct SaddleState: Codable {
    var version: Int = 1
    var lastRun: String?
    var lastFetch: String?
}

struct State {
    static func load() -> SaddleState {
        let path = Config.stateFile
        guard let data = FS.readFile(path)?.data(using: .utf8),
              let state = try? JSONDecoder().decode(SaddleState.self, from: data) else {
            return SaddleState()
        }
        return state
    }

    static func save(_ state: SaddleState) {
        let dir = Config.stateDir
        if !FS.isDirectory(dir) { _ = FS.createDirectory(dir) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        _ = FS.writeFile(Config.stateFile, contents: json)
    }

    static func touchLastRun() {
        var state = load()
        state.lastRun = DateFormatting.iso8601.string(from: Date())
        save(state)
    }

    static func touchLastFetch() {
        var state = load()
        state.lastFetch = DateFormatting.iso8601.string(from: Date())
        save(state)
    }

    static func shouldFetch() -> Bool {
        let state = load()
        guard let stamp = state.lastFetch,
              let date = DateFormatting.iso8601.date(from: stamp) else {
            return true
        }
        return Date().timeIntervalSince(date) > 86400
    }
}
