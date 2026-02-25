import Foundation

struct GitHub: ForgeProvider, Sendable {
    let hostname = "github.com"
    let displayName = "GitHub"

    private let http = ForgeHTTP(
        baseURL: "https://api.github.com",
        acceptHeader: "application/vnd.github+json"
    )

    func resolveToken() -> String? {
        let (output, rc) = Exec.run("/usr/bin/env", args: ["gh", "auth", "token"], timeout: 3)
        if rc == 0, !output.isEmpty { return output }
        if let envToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"],
           !envToken.isEmpty { return envToken }
        let tokenFile = Config.configDir + "/github-token"
        if let contents = FS.readFile(tokenFile) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    func fetchRepos(token: String, declaredPaths _: [String]) -> ForgeResult {
        nonisolated(unsafe) var personalRepos: [GitHubRepo] = []
        nonisolated(unsafe) var collabRepos: [GitHubRepo] = []
        nonisolated(unsafe) var starredRepos: [GitHubRepo] = []
        nonisolated(unsafe) var orgs: [GitHubOrg] = []
        nonisolated(unsafe) var user: GitHubUser?

        DispatchQueue.concurrentPerform(iterations: 5) { i in
            if i == 0 {
                personalRepos = http.getPaginated("/user/repos", token: token, params: [
                    ("affiliation", "owner"),
                    ("visibility", "all"),
                ])
            } else if i == 1 {
                collabRepos = http.getPaginated("/user/repos", token: token, params: [
                    ("affiliation", "collaborator"),
                ])
            } else if i == 2 {
                orgs = http.getPaginated("/user/orgs", token: token)
            } else if i == 3 {
                if let data = http.get("/user", token: token),
                   let decoded = try? JSONDecoder().decode(GitHubUser.self, from: data) {
                    user = decoded
                }
            } else {
                starredRepos = http.getPaginated("/user/starred", token: token)
            }
        }

        var orgRepos = Array(repeating: [GitHubRepo](), count: orgs.count)
        if !orgs.isEmpty {
            orgRepos.withUnsafeMutableBufferPointer { buf in
                nonisolated(unsafe) let buffer = buf
                let orgLogins = orgs.map(\.login)
                DispatchQueue.concurrentPerform(iterations: orgLogins.count) { i in
                    buffer[i] = http.getPaginated("/orgs/\(orgLogins[i])/repos", token: token)
                }
            }
        }

        var map: [String: RemoteRepoInfo] = [:]

        for repo in personalRepos {
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

        for repo in collabRepos {
            let key = "github.com/\(repo.fullName)".lowercased()
            if map[key] == nil {
                map[key] = Self.extract(repo, role: "collab")
            }
        }

        var starredURLs = Set<String>()
        for repo in starredRepos {
            let key = "github.com/\(repo.fullName)".lowercased()
            starredURLs.insert(key)
            if map[key] == nil {
                map[key] = Self.extract(repo, role: "starred")
            }
        }

        let orgNames = Set(orgs.map { $0.login.lowercased() })
        return ForgeResult(repos: map, orgNames: orgNames, starredURLs: starredURLs, authenticatedUser: user?.login.lowercased())
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
