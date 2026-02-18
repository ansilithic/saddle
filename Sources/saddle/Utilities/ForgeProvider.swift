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
    func fetchRepos(token: String) -> ForgeResult
}

enum Forge {
    static let providers: [any ForgeProvider] = [GitHub(), GitLab()]

    static func fetchAllRepos() -> ForgeResult {
        if let mockResult = loadMock() { return mockResult }

        var results = Array(repeating: ForgeResult(), count: providers.count)
        results.withUnsafeMutableBufferPointer { buf in
            nonisolated(unsafe) let buffer = buf
            DispatchQueue.concurrentPerform(iterations: providers.count) { i in
                let provider = providers[i]
                if let token = provider.resolveToken() {
                    buffer[i] = provider.fetchRepos(token: token)
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
        return merged
    }

    private static func loadMock() -> ForgeResult? {
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
    }
}

private struct MockForge: Decodable {
    let repos: [String: RemoteRepoInfo]
    let starred: [String]
    let user: String?
}
