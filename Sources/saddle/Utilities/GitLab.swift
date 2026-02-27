import Foundation

struct GitLab: ForgeProvider, Sendable {
    let hostname: String
    let displayName: String
    private let http: ForgeHTTP

    init(hostname: String = "gitlab.com") {
        self.hostname = hostname
        self.displayName = hostname == "gitlab.com" ? "GitLab" : "GitLab (\(hostname))"
        self.http = ForgeHTTP(
            baseURL: "https://\(hostname)/api/v4",
            acceptHeader: "application/json"
        )
    }

    func resolveToken() -> String? {
        let (output, rc) = Exec.run("/usr/bin/env", args: ["glab", "config", "get", "token", "--host", hostname], timeout: 3)
        if rc == 0, !output.isEmpty { return output }
        if let envToken = ProcessInfo.processInfo.environment["GITLAB_TOKEN"],
           !envToken.isEmpty { return envToken }
        return nil
    }

    func fetchRepos(token: String, declaredPaths: [String]) -> ForgeResult {
        // Fast bail for unreachable self-hosted instances (VPN down, etc.)
        if hostname != "gitlab.com", !http.reachable() {
            return ForgeResult()
        }

        var map: [String: RemoteRepoInfo] = [:]
        var starredURLs = Set<String>()

        var authenticatedUser: String?

        if !token.isEmpty {
            nonisolated(unsafe) var accessibleProjects: [GitLabProject] = []
            nonisolated(unsafe) var starredProjects: [GitLabProject] = []
            nonisolated(unsafe) var user: GitLabUser?

            DispatchQueue.concurrentPerform(iterations: 3) { i in
                if i == 0 {
                    // gitlab.com: membership filter avoids millions of public repos
                    // Self-hosted: no filter — token scoping limits visibility,
                    // and LDAP/group-inherited access doesn't set membership
                    let params: [(String, String)] = hostname == "gitlab.com"
                        ? [("membership", "true")]
                        : []
                    accessibleProjects = http.getPaginated("/projects", token: token, params: params)
                } else if i == 1 {
                    starredProjects = http.getPaginated("/projects", token: token, params: [
                        ("starred", "true"),
                    ])
                } else {
                    if let data = http.get("/user", token: token),
                       let decoded = try? JSONDecoder().decode(GitLabUser.self, from: data) {
                        user = decoded
                    }
                }
            }
            authenticatedUser = user?.username.lowercased()

            for project in accessibleProjects {
                map[keyFor(project)] = info(from: project)
            }
            for project in starredProjects {
                let key = keyFor(project)
                starredURLs.insert(key)
                if map[key] == nil {
                    map[key] = info(from: project)
                }
            }
        }

        // Targeted lookups for declared repos missing from bulk results
        let missingPaths = declaredPaths.filter { path in
            map["\(hostname)/\(path)".lowercased()] == nil
        }
        if !missingPaths.isEmpty {
            var lookups = Array<GitLabProject?>(repeating: nil, count: missingPaths.count)
            lookups.withUnsafeMutableBufferPointer { buf in
                nonisolated(unsafe) let buffer = buf
                DispatchQueue.concurrentPerform(iterations: missingPaths.count) { i in
                    let encoded = missingPaths[i].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?.replacingOccurrences(of: "/", with: "%2F") ?? missingPaths[i]
                    if let data = http.get("/projects/\(encoded)", token: token),
                       let project = try? JSONDecoder().decode(GitLabProject.self, from: data) {
                        buffer[i] = project
                    }
                }
            }
            for project in lookups.compactMap({ $0 }) {
                map[keyFor(project)] = info(from: project)
            }
        }

        return ForgeResult(repos: map, starredURLs: starredURLs, authenticatedUser: authenticatedUser)
    }

    private func keyFor(_ project: GitLabProject) -> String {
        "\(hostname)/\(project.pathWithNamespace)".lowercased()
    }

    private func info(from project: GitLabProject) -> RemoteRepoInfo {
        let isFork = project.forkedFromProject != nil
        return RemoteRepoInfo(
            visibility: project.visibility == "internal" ? "private" : (project.visibility ?? "private"),
            role: isFork ? "fork" : "owned",
            defaultBranch: project.defaultBranch ?? "",
            pushedAt: project.lastActivityAt ?? "",
            language: "",
            description: (project.description ?? "").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: ""),
            stargazers: project.starCount ?? 0,
            isArchived: project.archived ?? false
        )
    }

}
