import Foundation

struct GitLab: ForgeProvider, Sendable {
    let hostname = "gitlab.com"
    let displayName = "GitLab"

    private let http = ForgeHTTP(
        baseURL: "https://gitlab.com/api/v4",
        acceptHeader: "application/json"
    )

    func resolveToken() -> String? {
        let (output, rc) = Exec.run("/usr/bin/env", args: ["glab", "auth", "token"])
        if rc == 0, !output.isEmpty { return output }
        if let envToken = ProcessInfo.processInfo.environment["GITLAB_TOKEN"],
           !envToken.isEmpty { return envToken }
        let tokenFile = Config.configDir + "/gitlab-token"
        if let contents = FS.readFile(tokenFile) {
            let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    func fetchRepos(token: String) -> ForgeResult {
        let projects: [GitLabProject] = http.getPaginated("/projects", token: token, params: [
            ("membership", "true"),
        ])

        var map: [String: RemoteRepoInfo] = [:]
        for project in projects {
            let key = "gitlab.com/\(project.pathWithNamespace)".lowercased()
            let isFork = project.forkedFromProject != nil

            map[key] = RemoteRepoInfo(
                visibility: project.visibility ?? "private",
                role: isFork ? "fork" : "owned",
                defaultBranch: project.defaultBranch ?? "",
                pushedAt: project.lastActivityAt ?? "",
                language: "",
                description: project.description ?? "",
                stargazers: project.starCount ?? 0,
                isArchived: project.archived ?? false
            )
        }
        return ForgeResult(repos: map)
    }

}
