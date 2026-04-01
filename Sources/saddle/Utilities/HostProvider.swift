import Foundation

struct HostResult: Sendable {
    var repos: [String: RemoteRepoInfo] = [:]
    var orgNames: Set<String> = []
    var starredURLs: Set<String> = []
    var authenticatedUser: String?
}

enum Host {
    static func fetchAllRepos(declaredURLs: [String] = [], forceRefresh: Bool = false) async -> HostResult {
        if let mockResult = loadMock() { return mockResult }

        if !forceRefresh, let cached = State.loadHostCache() {
            return cached
        }

        let github = GitHub()
        guard let token = github.resolveToken() else {
            return HostResult()
        }

        let paths = declaredURLs.compactMap { url -> String? in
            let host = URLHelpers.host(from: url)
            guard host == "github.com" else { return nil }
            return URLHelpers.pathAfterHost(from: url)
        }

        let result = await github.fetchRepos(token: token, declaredPaths: paths)
        State.saveHostCache(result)
        return result
    }

    private static func loadMock() -> HostResult? {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["SADDLE_HOST_MOCK"],
              !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let mock = try? JSONDecoder().decode(MockHost.self, from: data)
        else { return nil }

        var result = HostResult()
        result.repos = mock.repos
        result.starredURLs = Set(mock.starred)
        result.authenticatedUser = mock.user
        return result
        #else
        return nil
        #endif
    }
}

private struct MockHost: Decodable {
    let repos: [String: RemoteRepoInfo]
    let starred: [String]
    let user: String?
}
