import Foundation

struct GitHub: Sendable {
    static let hostname = "github.com"
    static let apiBaseURL = "https://api.github.com"
    static let apiAccept = "application/vnd.github+json"

    private let http = HostHTTP(baseURL: GitHub.apiBaseURL, acceptHeader: GitHub.apiAccept)

    func resolveToken() -> String? {
        CredentialStore.platform.get(account: GitHub.hostname)
    }

    func fetchRepos(token: String, declaredPaths: [String]) async -> HostResult {
        // Fetch personal, collab, orgs, user, starred concurrently
        async let personalRepos: [GitHubRepo] = http.getPaginated("/user/repos", token: token, params: [
            ("affiliation", "owner"),
            ("visibility", "all"),
        ])
        async let collabRepos: [GitHubRepo] = http.getPaginated("/user/repos", token: token, params: [
            ("affiliation", "collaborator"),
        ])
        async let orgs: [GitHubOrg] = http.getPaginated("/user/orgs", token: token)
        async let userResult: GitHubUser? = {
            guard let data = await http.get("/user", token: token) else { return nil }
            return try? JSONDecoder().decode(GitHubUser.self, from: data)
        }()
        async let starredRepos: [GitHubRepo] = http.getPaginated("/user/starred", token: token)

        let (personal, collab, orgList, user, starred) = await (personalRepos, collabRepos, orgs, userResult, starredRepos)

        // Fetch org repos concurrently
        let orgRepos: [[GitHubRepo]] = await withTaskGroup(of: (Int, [GitHubRepo]).self) { group in
            for (i, org) in orgList.enumerated() {
                group.addTask {
                    let repos: [GitHubRepo] = await http.getPaginated("/orgs/\(org.login)/repos", token: token)
                    return (i, repos)
                }
            }
            var results = Array(repeating: [GitHubRepo](), count: orgList.count)
            for await (i, repos) in group {
                results[i] = repos
            }
            return results
        }

        var map: [String: RemoteRepoInfo] = [:]

        for repo in personal {
            let key = "github.com/\(repo.fullName)".lowercased()
            map[key] = Self.extract(repo, role: "owned")
        }

        for repos in orgRepos {
            for repo in repos {
                let key = "github.com/\(repo.fullName)".lowercased()
                if map[key] == nil {
                    map[key] = Self.extract(repo, role: "owned")
                }
            }
        }

        for repo in collab {
            let key = "github.com/\(repo.fullName)".lowercased()
            if map[key] == nil {
                map[key] = Self.extract(repo, role: "collab")
            }
        }

        var starredURLs = Set<String>()
        for repo in starred {
            let key = "github.com/\(repo.fullName)".lowercased()
            starredURLs.insert(key)
            if map[key] == nil {
                map[key] = Self.extract(repo, role: "starred")
            }
        }

        // Fetch declared repos not found via owned/collab/starred
        let missingPaths = declaredPaths.filter { map["github.com/\($0)".lowercased()] == nil }
        if !missingPaths.isEmpty {
            let fetched: [GitHubRepo?] = await withTaskGroup(of: (Int, GitHubRepo?).self) { group in
                for (i, path) in missingPaths.enumerated() {
                    group.addTask {
                        guard let data = await http.get("/repos/\(path)", token: token),
                              let repo = try? JSONDecoder().decode(GitHubRepo.self, from: data) else {
                            return (i, nil)
                        }
                        return (i, repo)
                    }
                }
                var results = Array(repeating: (GitHubRepo?).none, count: missingPaths.count)
                for await (i, repo) in group {
                    results[i] = repo
                }
                return results
            }
            for repo in fetched {
                guard let repo else { continue }
                let key = "github.com/\(repo.fullName)".lowercased()
                if map[key] == nil {
                    map[key] = Self.extract(repo, role: "public")
                }
            }
        }

        let orgNames = Set(orgList.map { $0.login.lowercased() })
        return HostResult(repos: map, orgNames: orgNames, starredURLs: starredURLs, authenticatedUser: user?.login.lowercased())
    }

    // MARK: - Private

    private static func extract(_ repo: GitHubRepo, role: String) -> RemoteRepoInfo {
        let vis = repo.visibility?.lowercased() ?? "private"
        let isFork = repo.fork == true
        let effectiveRole = isFork ? "fork" : role
        return RemoteRepoInfo(
            visibility: vis,
            role: effectiveRole,
            defaultBranch: repo.defaultBranch ?? "",
            pushedAt: repo.pushedAt ?? "",
            language: repo.language ?? "",
            description: repo.description ?? "",
            stargazers: repo.stargazersCount ?? 0,
            isArchived: repo.archived ?? false
        )
    }
}
