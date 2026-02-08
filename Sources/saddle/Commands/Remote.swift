import ArgumentParser
import CLICore
import Foundation

struct Remote: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List GitHub repos not cloned locally."
    )

    private static let colPadding = 4

    func run() {
        let manifest: Manifest?
        let path = Config.manifestPath
        if FS.exists(path) {
            manifest = parseManifest(at: path)
        } else {
            manifest = nil
        }

        let devDir = manifest?.root ?? FS.expandPath(Parser.defaultRoot)

        let visibilityMap = GitHubAPI.fetchVisibility()

        let discoveredPaths = FS.findRepos(in: devDir)
        let repoCount = discoveredPaths.count
        var localURLs = Array(repeating: "", count: repoCount)

        localURLs.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: repoCount) { i in
                if let url = GitHelpers.getRemoteURL(at: discoveredPaths[i]) {
                    buffer[i] = URLHelpers.normalize(url)
                }
            }
        }

        let localSet = Set(localURLs.filter { !$0.isEmpty })

        let remoteOnly = visibilityMap
            .filter { !localSet.contains($0.key) }
            .sorted { $0.key < $1.key }

        if remoteOnly.isEmpty {
            print()
            print(styled("All GitHub repos are cloned locally.", .green))
            print()
            return
        }

        struct RemoteRepo {
            let name: String
            let visibility: String
            let type: String
        }

        let repos = remoteOnly.map { (normalizedURL, vis) -> RemoteRepo in
            let name = String(normalizedURL.dropFirst("github.com/".count))
            let type: String
            if vis == "fork" {
                type = "fork"
            } else if vis.hasSuffix("collab") {
                type = "collaborator"
            } else {
                type = "owned"
            }
            return RemoteRepo(name: name, visibility: vis, type: type)
        }

        let p = Self.colPadding
        let colRepo = max("Repository".count, repos.map { $0.name.count }.max() ?? 0) + p
        let colVis = max("Visibility".count, repos.map { $0.visibility.count }.max() ?? 0) + p
        let colType = max("Type".count, repos.map { $0.type.count }.max() ?? 0) + p
        let tableWidth = colRepo + colVis + colType + 3

        print()
        let header = "   "
            + "Repository".padding(toLength: colRepo, withPad: " ", startingAt: 0)
            + "Visibility".padding(toLength: colVis, withPad: " ", startingAt: 0)
            + "Type"
        print(styled(header, .dim))
        print(styled("\u{2500}".repeating(tableWidth), .dim))

        for repo in repos {
            let namePadded = repo.name.padding(toLength: colRepo, withPad: " ", startingAt: 0)
            let visColor: Color
            if repo.visibility.hasSuffix("collab") {
                visColor = .cyan
            } else {
                switch repo.visibility {
                case "public": visColor = .yellow
                case "fork": visColor = .blue
                default: visColor = .dim
                }
            }
            let visPadded = repo.visibility.padding(toLength: colVis, withPad: " ", startingAt: 0)
            let typeColor: Color
            switch repo.type {
            case "fork": typeColor = .blue
            case "collaborator": typeColor = .cyan
            default: typeColor = .dim
            }
            print("   \(styled(namePadded, .white))\(styled(visPadded, visColor))\(styled(repo.type, typeColor))")
        }

        print()
        var parts: [String] = []
        let forkCount = repos.filter { $0.type == "fork" }.count
        let collabCount = repos.filter { $0.type == "collaborator" }.count
        let ownedCount = repos.filter { $0.type == "owned" }.count
        parts.append(styled("\(repos.count) remote", .white))
        if ownedCount > 0 { parts.append(styled("\(ownedCount) owned", .dim)) }
        if forkCount > 0 { parts.append(styled("\(forkCount) forks", .blue)) }
        if collabCount > 0 { parts.append(styled("\(collabCount) collaborator", .cyan)) }
        Output.printSummary(parts)
    }

    private func parseManifest(at path: String) -> Manifest? {
        do {
            return try Parser.parse(at: path)
        } catch {
            return nil
        }
    }
}
