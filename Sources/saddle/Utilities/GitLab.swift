import Foundation

struct GitLab: ForgeProvider, Sendable {
    let hostname = "gitlab.com"
    let displayName = "GitLab"

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
        let projects: [GitLabProject] = apiGetPaginated("/projects", token: token, params: [
            ("membership", "true"),
            ("per_page", "100"),
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

    // MARK: - Private

    private func apiGet(_ path: String, token: String, params: [(String, String)] = []) -> Data? {
        var urlString = "https://gitlab.com/api/v4\(path)"
        if !params.isEmpty {
            let query = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
            urlString += "?\(query)"
        }
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
}
