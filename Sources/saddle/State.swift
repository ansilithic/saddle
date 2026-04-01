import Foundation

struct SaddleState: Codable {
    var version: Int = 1
    var lastRun: String?
    var lastFetch: String?
}

struct HostCache: Codable {
    let repos: [String: RemoteRepoInfo]
    let starredURLs: [String]
    let authenticatedUser: String?
    let timestamp: String

    init(from result: HostResult) {
        self.repos = result.repos
        self.starredURLs = Array(result.starredURLs)
        self.authenticatedUser = result.authenticatedUser
        self.timestamp = DateFormatting.iso8601.string(from: Date())
    }

    func toResult() -> HostResult {
        HostResult(
            repos: repos,
            orgNames: [],
            starredURLs: Set(starredURLs),
            authenticatedUser: authenticatedUser
        )
    }
}

struct State {
    private static let hostCacheTTL: TimeInterval = 600 // 10 minutes

    static func load() -> SaddleState {
        guard let data = try? FS.readFile(Paths.stateFile).data(using: .utf8),
              let state = try? JSONDecoder().decode(SaddleState.self, from: data) else {
            return SaddleState()
        }
        return state
    }

    static func save(_ state: SaddleState) {
        do {
            let dir = Paths.dataDir
            if !FS.isDirectory(dir) { try FS.createDirectory(dir) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            guard let json = String(data: data, encoding: .utf8) else { return }
            try FS.writeFile(Paths.stateFile, contents: json)
        } catch {
            Log.error("Failed to save state: \(error)")
        }
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

    // MARK: - Host Cache

    static func loadHostCache() -> HostResult? {
        guard let raw = try? FS.readFile(Paths.hostCachePath).data(using: .utf8),
              let cache = try? JSONDecoder().decode(HostCache.self, from: raw),
              let date = DateFormatting.iso8601.date(from: cache.timestamp),
              Date().timeIntervalSince(date) < hostCacheTTL else {
            return nil
        }
        return cache.toResult()
    }

    static func saveHostCache(_ result: HostResult) {
        do {
            let dir = Paths.cacheDir
            if !FS.isDirectory(dir) { try FS.createDirectory(dir) }
            let cache = HostCache(from: result)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            guard let json = String(data: data, encoding: .utf8) else { return }
            try FS.writeFile(Paths.hostCachePath, contents: json)
        } catch {
            Log.error("Failed to save host cache: \(error)")
        }
    }
}
