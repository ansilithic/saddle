import Foundation

struct GitHub: ForgeProvider, Sendable {
    let hostname = "github.com"
    let displayName = "GitHub"

    func resolveToken() -> String? {
        let (output, rc) = Exec.run("/usr/bin/env", args: ["gh", "auth", "token"])
        if rc == 0, !output.isEmpty { return output }
        let tokenFile = Config.configDir + "/github-token"
        if let contents = FS.readFile(tokenFile) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    func fetchRepos(token: String) -> ForgeResult {
        nonisolated(unsafe) var personalRepos: [GitHubRepo] = []
        nonisolated(unsafe) var collabRepos: [GitHubRepo] = []
        nonisolated(unsafe) var starredRepos: [GitHubRepo] = []
        nonisolated(unsafe) var orgs: [GitHubOrg] = []
        nonisolated(unsafe) var user: GitHubUser?

        DispatchQueue.concurrentPerform(iterations: 5) { i in
            if i == 0 {
                personalRepos = apiGetPaginated("/user/repos", token: token, params: [
                    ("affiliation", "owner"),
                    ("visibility", "all"),
                ])
            } else if i == 1 {
                collabRepos = apiGetPaginated("/user/repos", token: token, params: [
                    ("affiliation", "collaborator"),
                ])
            } else if i == 2 {
                if let data = apiGet("/user/orgs", token: token),
                   let decoded = try? JSONDecoder().decode([GitHubOrg].self, from: data) {
                    orgs = decoded
                }
            } else if i == 3 {
                if let data = apiGet("/user", token: token),
                   let decoded = try? JSONDecoder().decode(GitHubUser.self, from: data) {
                    user = decoded
                }
            } else {
                starredRepos = apiGetPaginated("/user/starred", token: token)
            }
        }

        var orgRepos = Array(repeating: [GitHubRepo](), count: orgs.count)
        if !orgs.isEmpty {
            orgRepos.withUnsafeMutableBufferPointer { buf in
                nonisolated(unsafe) let buffer = buf
                let orgLogins = orgs.map(\.login)
                DispatchQueue.concurrentPerform(iterations: orgLogins.count) { i in
                    buffer[i] = apiGetPaginated("/orgs/\(orgLogins[i])/repos", token: token)
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

    private func apiGet(_ path: String, token: String, params: [(String, String)] = []) -> Data? {
        var urlString = "https://api.github.com\(path)"
        if !params.isEmpty {
            let query = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
            urlString += "?\(query)"
        }
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        nonisolated(unsafe) var result: Data?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }

    private func apiGetPaginated<T: Decodable>(_ path: String, token: String, params: [(String, String)] = []) -> [T] {
        let decoder = JSONDecoder()
        var all: [T] = []
        var page = 1
        while true {
            var pageParams = params
            pageParams.append(("per_page", "100"))
            pageParams.append(("page", "\(page)"))
            guard let data = apiGet(path, token: token, params: pageParams),
                  let items = try? decoder.decode([T].self, from: data) else { break }
            if items.isEmpty { break }
            all.append(contentsOf: items)
            if items.count < 100 { break }
            page += 1
        }
        return all
    }

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
