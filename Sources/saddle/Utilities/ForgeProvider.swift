import Foundation

struct ForgeResult {
    var repos: [String: RemoteRepoInfo] = [:]
    var orgNames: Set<String> = []
    var starredURLs: Set<String> = []
    var authenticatedUser: String?
}

protocol ForgeProvider: Sendable {
    var hostname: String { get }
    var displayName: String { get }

    func resolveToken() -> String?
    func fetchRepos(token: String, declaredPaths: [String]) -> ForgeResult
}

enum Forge {
    private static let defaultProviders: [any ForgeProvider] = [GitHub(), GitLab()]
    private static let defaultHostnames: Set<String> = ["github.com", "gitlab.com"]

    static func fetchAllRepos(declaredURLs: [String] = [], forceRefresh: Bool = false) -> ForgeResult {
        if let mockResult = loadMock() { return mockResult }

        if !forceRefresh, let cached = State.loadForgeCache() {
            return cached
        }

        let extraHosts = Set(declaredURLs.map { URLHelpers.host(from: $0) })
            .subtracting(defaultHostnames)
            .filter { !$0.isEmpty }
        let providers: [any ForgeProvider] = defaultProviders + extraHosts.sorted().map { GitLab(hostname: $0) }

        let pathsByHost = declaredURLs.reduce(into: [String: [String]]()) { result, url in
            let host = URLHelpers.host(from: url)
            let path = URLHelpers.pathAfterHost(from: url)
            if !host.isEmpty, !path.isEmpty {
                result[host, default: []].append(path)
            }
        }

        var results = Array(repeating: ForgeResult(), count: providers.count)
        results.withUnsafeMutableBufferPointer { buf in
            nonisolated(unsafe) let buffer = buf
            DispatchQueue.concurrentPerform(iterations: providers.count) { i in
                let provider = providers[i]
                let token = provider.resolveToken()
                let paths = pathsByHost[provider.hostname] ?? []
                if token != nil || !paths.isEmpty {
                    buffer[i] = provider.fetchRepos(token: token ?? "", declaredPaths: paths)
                }
            }
        }
        var merged = ForgeResult()
        for result in results {
            for (key, value) in result.repos {
                merged.repos[key] = value
            }
            merged.orgNames.formUnion(result.orgNames)
            merged.starredURLs.formUnion(result.starredURLs)
            if merged.authenticatedUser == nil {
                merged.authenticatedUser = result.authenticatedUser
            }
        }

        State.saveForgeCache(merged)
        return merged
    }

    private static func loadMock() -> ForgeResult? {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["SADDLE_FORGE_MOCK"],
              !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let mock = try? JSONDecoder().decode(MockForge.self, from: data)
        else { return nil }

        var result = ForgeResult()
        result.repos = mock.repos
        result.starredURLs = Set(mock.starred)
        result.authenticatedUser = mock.user
        return result
        #else
        return nil
        #endif
    }
}

private struct MockForge: Decodable {
    let repos: [String: RemoteRepoInfo]
    let starred: [String]
    let user: String?
}
