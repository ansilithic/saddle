import Foundation

enum GitHubAPI {
    /// Batch-fetch visibility for GitHub repos (owned + collaborator).
    /// Returns a map of normalized URL -> "public", "private", "fork", or "collaborator".
    static func fetchVisibility() -> [String: String] {
        var ownedResult: (String, Int32) = ("", 1)
        var collabResult: (String, Int32) = ("", 1)

        DispatchQueue.concurrentPerform(iterations: 2) { i in
            if i == 0 {
                ownedResult = Exec.run("/usr/bin/env", args: [
                    "gh", "repo", "list", "--limit", "500",
                    "--json", "nameWithOwner,visibility,isFork"
                ])
            } else {
                collabResult = Exec.run("/usr/bin/env", args: [
                    "gh", "api", "user/repos", "--paginate",
                    "--method", "GET",
                    "-f", "affiliation=collaborator",
                    "-f", "per_page=100",
                    "--jq", "[.[] | {nameWithOwner: .full_name, visibility: .visibility, isFork: .fork}]"
                ])
            }
        }

        var map: [String: String] = [:]

        if ownedResult.1 == 0, !ownedResult.0.isEmpty,
           let data = ownedResult.0.data(using: .utf8),
           let repos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for repo in repos {
                guard let nwo = repo["nameWithOwner"] as? String else { continue }
                let key = "github.com/\(nwo)".lowercased()
                if repo["isFork"] as? Bool == true {
                    map[key] = "fork"
                } else if let vis = repo["visibility"] as? String {
                    map[key] = vis.lowercased()
                }
            }
        }

        if collabResult.1 == 0, !collabResult.0.isEmpty {
            let jsonStr = "[\(collabResult.0.replacingOccurrences(of: "]\n[", with: ","))]"
                .replacingOccurrences(of: "[[", with: "[")
                .replacingOccurrences(of: "]]", with: "]")
            if let data = jsonStr.data(using: .utf8),
               let repos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for repo in repos {
                    guard let nwo = repo["nameWithOwner"] as? String else { continue }
                    let key = "github.com/\(nwo)".lowercased()
                    if map[key] == nil {
                        let vis = (repo["visibility"] as? String)?.lowercased() ?? "private"
                        map[key] = "\(vis) collab"
                    }
                }
            }
        }

        return map
    }
}
