import ArgumentParser
import CLICore
import Foundation

struct Deps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deps",
        abstract: "Show the dependency graph of tracked repos."
    )

    @Argument(help: "Optional repo (e.g. avranet/avranet). If omitted, shows the full graph.")
    var repo: String?

    @Flag(name: .long, help: "Reverse view: who depends on this repo?")
    var downstream = false

    func run() throws {
        let path = Paths.manifestPath
        guard FS.exists(path) else {
            Output.error("No manifest found at \(FS.shortenPath(path))")
            throw ExitCode.failure
        }
        guard let manifest = Parser.parseOrNil(at: path) else {
            throw ExitCode.failure
        }
        if manifest.repos.isEmpty {
            print(styled("No repos declared in manifest.", .dim))
            return
        }

        // Resolve full dep graph (manifest + hook.sh annotations merged).
        let resolved: (levels: [[String]], deps: [String: [String]])
        do {
            resolved = try DependencyResolver.resolveLevels(manifest.repos, manifestDeps: manifest.dependencies)
        } catch {
            Output.error("\(error)")
            throw ExitCode.failure
        }

        let normalizedToOriginal: [String: String] = Dictionary(
            uniqueKeysWithValues: manifest.repos.map { (URLHelpers.normalize($0), $0) }
        )

        // Build a reverse adjacency map for the downstream view.
        var downstreamMap: [String: [String]] = [:]
        for (src, targets) in resolved.deps {
            for t in targets {
                downstreamMap[t, default: []].append(src)
            }
        }

        if let target = repo {
            try printSingle(target: target, deps: resolved.deps, downstreamMap: downstreamMap, manifestRepos: normalizedToOriginal)
        } else {
            printFullGraph(levels: resolved.levels, deps: resolved.deps, downstreamMap: downstreamMap, manifestRepos: normalizedToOriginal)
        }
    }

    // MARK: - Single-repo view

    private func printSingle(
        target: String,
        deps: [String: [String]],
        downstreamMap: [String: [String]],
        manifestRepos: [String: String]
    ) throws {
        let normalized = DependencyResolver.normalizeDep(target)
        guard manifestRepos[normalized] != nil else {
            Output.error("Repo not in manifest: \(target)")
            throw ExitCode.failure
        }

        print()
        print("  " + styled(URLHelpers.pathAfterHost(from: normalized), .bold))

        let edges = downstream ? (downstreamMap[normalized] ?? []) : (deps[normalized] ?? [])
        let label = downstream ? "depended on by" : "depends on"

        if edges.isEmpty {
            print("  " + styled("(\(label) nothing)", .dim))
            return
        }

        print("  " + styled(label, .dim) + " " + styled("\(edges.count)", .dim))
        let sorted = edges.sorted()
        for (i, dep) in sorted.enumerated() {
            let isLast = i == sorted.count - 1
            let prefix = isLast ? "└─" : "├─"
            print("    " + styled(prefix, .dim) + " " + styledRepoPath(URLHelpers.pathAfterHost(from: dep)))
        }
        print()
    }

    // MARK: - Full graph view

    private func printFullGraph(
        levels: [[String]],
        deps: [String: [String]],
        downstreamMap: [String: [String]],
        manifestRepos: [String: String]
    ) {
        let depCount = deps.values.reduce(0) { $0 + $1.count }
        print()
        print("  " + styled("\(manifestRepos.count) repos", .bold) + "  " + styled("\(levels.count) levels", .dim) + "  " + styled("\(depCount) edges", .dim))
        print()

        for (i, level) in levels.enumerated() {
            let n = level.count
            let header = "Level \(i + 1)  ·  \(n) repo\(n == 1 ? "" : "s")"
            print("  " + styled(header, .bold))

            // Within the level, list each repo + its (upstream) deps inline.
            // Sort by relative path for stable output.
            let sortedLevel = level.sorted()
            for url in sortedLevel {
                let edges = deps[url] ?? []
                let line = "    " + styledRepoPath(URLHelpers.pathAfterHost(from: url))
                if edges.isEmpty {
                    print(line)
                } else {
                    let names = edges.sorted().map { URLHelpers.pathAfterHost(from: $0) }
                    let depList = names.joined(separator: ", ")
                    let arrow = styled("← needs", .dim)
                    print(line + "  " + arrow + " " + styled(depList, .dim))
                }
            }
            print()
        }

        // Highlight orchestrator nodes (those with the most downstream consumers).
        let orchestrators = downstreamMap
            .map { (key: $0.key, count: $0.value.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(5)
        if !orchestrators.isEmpty {
            print("  " + styled("Most depended on", .bold))
            for o in orchestrators {
                let label = "\(o.count) downstream"
                print("    " + styledRepoPath(URLHelpers.pathAfterHost(from: o.key)) + "  " + styled(label, .dim))
            }
            print()
        }
    }
}
