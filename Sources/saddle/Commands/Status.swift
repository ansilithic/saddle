import ArgumentParser
import CLICore
import Foundation

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show git status of all repos in ~/Developer."
    )

    func run() {
        let manifest: Manifest?
        let path = Config.manifestPath
        if FS.exists(path) {
            manifest = parseManifest(at: path)
        } else {
            manifest = nil
        }

        let devDir = manifest?.root ?? FS.expandPath(Parser.defaultRoot)

        let declaredURLs = manifest?.urls ?? []
        let normalizedDeclared = Set(declaredURLs.map { URLHelpers.normalize($0) })

        let discoveredPaths = FS.findRepos(in: devDir)

        let visibilityMap = GitHubAPI.fetchVisibility()

        let repoCount = discoveredPaths.count
        let placeholder = RepoInfo(
            relativePath: "", fullPath: "", remoteURL: nil,
            branch: "", status: "", statusColor: .dim,
            lastCommitTime: "", saddled: false, hasHook: false,
            visibility: ""
        )
        var repoInfos = Array(repeating: placeholder, count: repoCount)

        repoInfos.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: repoCount) { i in
                let repoPath = discoveredPaths[i]
                let relativePath = String(repoPath.dropFirst(devDir.count + 1))
                let remoteURL = GitHelpers.getRemoteURL(at: repoPath)
                let normalized = remoteURL.map { URLHelpers.normalize($0) }
                let saddled = normalized.map { normalizedDeclared.contains($0) } ?? false
                let git = GitHelpers.info(at: repoPath)
                let hasHook = remoteURL.map { Sync.findHook(for: $0) != nil } ?? false
                let visibility: String
                if let url = remoteURL {
                    visibility = visibilityMap[URLHelpers.normalize(url)] ?? ""
                } else {
                    visibility = "local"
                }

                buffer[i] = RepoInfo(
                    relativePath: relativePath,
                    fullPath: repoPath,
                    remoteURL: remoteURL,
                    branch: git.branch,
                    status: git.status,
                    statusColor: git.statusColor,
                    lastCommitTime: git.lastCommitTime,
                    saddled: saddled,
                    hasHook: hasHook,
                    visibility: visibility
                )
            }
        }

        var repos: [RepoInfo] = []
        var matchedNormalized = Set<String>()
        for repo in repoInfos {
            repos.append(repo)
            if repo.saddled, let url = repo.remoteURL {
                matchedNormalized.insert(URLHelpers.normalize(url))
            }
        }

        let missingURLs = declaredURLs.filter { !matchedNormalized.contains(URLHelpers.normalize($0)) }

        print()
        if manifest != nil {
            print(styled("Manifest", .bold) + "        " + styled(Sync.shortenPath(path), .darkGray))
        }
        print(styled("Hooks", .bold) + "           " + styled(Sync.shortenPath(Config.hooksDir), .darkGray))
        print(styled("Developer Root", .bold) + "  " + styled(Sync.shortenPath(devDir), .darkGray))

        if !repos.isEmpty {
            printReposSection(repos)
        }

        if !missingURLs.isEmpty {
            printMissingSection(missingURLs)
        }

        if repos.isEmpty && missingURLs.isEmpty {
            print()
            print(styled("No git repos found in \(Sync.shortenPath(devDir))", .dim))
        }

        print()
        var parts: [String] = []
        parts.append(styled("\(repos.count) repos", .white))
        let saddledCount = repos.filter(\.saddled).count
        if saddledCount > 0 { parts.append(styled("\(saddledCount) saddled", .cyan)) }
        if !missingURLs.isEmpty { parts.append(styled("\(missingURLs.count) missing", .red)) }
        let dirtyCount = repos.filter { $0.statusColor == .yellow }.count
        if dirtyCount > 0 { parts.append(styled("\(dirtyCount) dirty", .yellow)) }
        Output.printSummary(parts)
    }

    private func parseManifest(at path: String) -> Manifest? {
        do {
            return try Parser.parse(at: path)
        } catch {
            print(styled("Parse error: \(error)", .red))
            return nil
        }
    }

    // MARK: - Display

    private static let colPadding = 4
    private static let tableWidth = 140

    private func printReposSection(_ repos: [RepoInfo]) {
        let p = Self.colPadding

        let colRepo = max("Repository".count, repos.map { $0.relativePath.count }.max() ?? 0) + p
        let colBranch = max("Branch".count, repos.map { $0.branch.count }.max() ?? 0) + p
        let colVis = max("Visibility".count, repos.map { $0.visibility.count }.max() ?? 0) + p
        let colStatus = max("Local Status".count, repos.map { $0.status.count }.max() ?? 0) + p
        let tableWidth = colRepo + colBranch + colVis + colStatus + 20

        print()
        let header = "   "
            + "Repository".padding(toLength: colRepo, withPad: " ", startingAt: 0)
            + "Branch".padding(toLength: colBranch, withPad: " ", startingAt: 0)
            + "Visibility".padding(toLength: colVis, withPad: " ", startingAt: 0)
            + "Local Status".padding(toLength: colStatus, withPad: " ", startingAt: 0)
            + "Last Commit"
        print(styled(header, .dim))
        print(styled("\u{2500}".repeating(tableWidth), .dim))

        for repo in repos {
            let indicator: String
            if repo.hasHook {
                indicator = styled("\u{25CF}", .blue)
            } else if repo.saddled {
                indicator = styled("\u{25CF}", .dim, .green)
            } else {
                indicator = styled("\u{25CF}", .dim, .red)
            }
            let namePadded = repo.relativePath.padding(toLength: colRepo, withPad: " ", startingAt: 0)
            let branch = repo.branch.padding(toLength: colBranch, withPad: " ", startingAt: 0)
            let visColor: Color
            if repo.visibility.hasSuffix("collab") {
                visColor = .cyan
            } else {
                switch repo.visibility {
                case "public": visColor = .yellow
                case "local": visColor = .gray
                default: visColor = .dim
                }
            }
            let vis = repo.visibility.padding(toLength: colVis, withPad: " ", startingAt: 0)
            let status = repo.status.padding(toLength: colStatus, withPad: " ", startingAt: 0)
            let commitTime = repo.lastCommitTime.isEmpty ? ""
                : styled(repo.lastCommitTime, commitTimeColor(repo.lastCommitTime))

            let branchColor: Color = repo.branch == "main" || repo.branch == "master" ? .green : .orange
            let nameCol = repo.saddled ? namePadded : styled(namePadded, .dim)

            print("\(indicator)  \(nameCol)\(styled(branch, branchColor))\(styled(vis, visColor))\(styled(status, repo.statusColor))\(commitTime)")
        }
    }

    private func commitTimeColor(_ time: String) -> Color {
        if time.contains("hour") || time.contains("minute") || time.contains("second") { return .green }
        if time.hasSuffix("days ago"), let n = Int(time.split(separator: " ").first ?? ""), n <= 7 { return .cyan }
        if time.contains("day") { return .yellow }
        if time.contains("week") { return .yellow }
        if time.contains("month") { return .orange }
        return .gray
    }

    private func printMissingSection(_ urls: [String]) {
        print()
        print(styled("  Missing", .dim))
        print(styled("\u{2500}".repeating(Self.tableWidth), .dim))

        for (i, url) in urls.enumerated() {
            let isLast = i == urls.count - 1
            let connector = isLast ? "\u{2514}\u{2500}" : "\u{251C}\u{2500}"
            print("\(styled(connector, .dim)) \(styled(url, .red))")
        }
    }
}
