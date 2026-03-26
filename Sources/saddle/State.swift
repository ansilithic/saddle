import Foundation

struct SaddleState: Codable {
    var version: Int = 1
    var lastRun: String?
    var lastFetch: String?
    var lastForge: String?
}

/// Cached forge API result, stored as JSON.
struct ForgeCache: Codable {
    let repos: [String: RemoteRepoInfo]
    let starredURLs: [String]
    let authenticatedUser: String?
    let timestamp: String

    init(from result: ForgeResult) {
        self.repos = result.repos
        self.starredURLs = Array(result.starredURLs)
        self.authenticatedUser = result.authenticatedUser
        self.timestamp = DateFormatting.iso8601.string(from: Date())
    }

    func toResult() -> ForgeResult {
        ForgeResult(
            repos: repos,
            orgNames: [],
            starredURLs: Set(starredURLs),
            authenticatedUser: authenticatedUser
        )
    }
}

struct State {
    private static let forgeCacheTTL: TimeInterval = 600 // 10 minutes

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

    // MARK: - Forge Cache

    private static var forgeCachePath: String { "\(Config.stateDir)/forge-cache.json" }

    static func loadForgeCache() -> ForgeResult? {
        guard let raw = FS.readFile(forgeCachePath)?.data(using: .utf8),
              let cache = try? JSONDecoder().decode(ForgeCache.self, from: raw),
              let date = DateFormatting.iso8601.date(from: cache.timestamp),
              Date().timeIntervalSince(date) < forgeCacheTTL else {
            return nil
        }
        return cache.toResult()
    }

    static func saveForgeCache(_ result: ForgeResult) {
        let dir = Config.stateDir
        if !FS.isDirectory(dir) { _ = FS.createDirectory(dir) }
        let cache = ForgeCache(from: result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(cache),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = FS.writeFile(forgeCachePath, contents: json)
    }
}
