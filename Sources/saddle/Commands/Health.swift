import ArgumentParser
import CLICore
import Foundation

struct Health: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show file-presence health for all repos."
    )

    @Flag(help: "Show only equipped repos (in manifest).")
    var equipped = false

    @Flag(help: "Show only stray repos (not in manifest).")
    var stray = false

    @Flag(help: "Show only healthy repos (all files present).")
    var healthy = false

    @Flag(help: "Show only unhealthy repos (missing files).")
    var unhealthy = false

    @Option(help: "Show only repos owned by <owner>.")
    var owner: String?

    func run() {
        let spinner = ProgressSpinner()
        spinner.label = styled("Scanning\u{2026}", .dim)
        spinner.start()

        let (_, devDir, declaredURLs) = Parser.loadManifest()
        let normalizedDeclared = Set(declaredURLs.map { URLHelpers.normalize($0) })

        let discoveredPaths = FS.findRepos(in: devDir)
        let repoCount = discoveredPaths.count

        var results = Array(repeating: HealthInfo(
            relativePath: "", fullPath: "", remoteURL: nil, owner: "local",
            saddled: false, hasReadme: false, hasGitignore: false,
            hasMakefile: false, hasLicense: false,
            hasHealthHook: false, hookPassed: false
        ), count: repoCount)

        let scanLock = NSLock()
        nonisolated(unsafe) var scanned = 0

        results.withUnsafeMutableBufferPointer { buf in
            nonisolated(unsafe) let buffer = buf
            DispatchQueue.concurrentPerform(iterations: repoCount) { i in
                let repoPath = discoveredPaths[i]
                let relativePath = String(repoPath.dropFirst(devDir.count + 1))

                let (remoteURL, _) = Exec.git("config", "remote.origin.url", at: repoPath)
                let normalized = remoteURL.isEmpty ? nil : URLHelpers.normalize(remoteURL)
                let saddled = normalized.map { normalizedDeclared.contains($0) } ?? false
                let owner = remoteURL.isEmpty ? "local" : URLHelpers.owner(from: remoteURL)

                var hasHealthHook = false
                var hookPassed = false

                if !remoteURL.isEmpty,
                   let resolution = HookResolver.resolve(for: remoteURL, lifecycle: .health) {
                    hasHealthHook = true
                    let result = HookResolver.execute(resolution, at: repoPath)
                    if case .ran(_, let exitCode) = result {
                        hookPassed = exitCode == 0
                    }
                }

                buffer[i] = HealthInfo(
                    relativePath: relativePath,
                    fullPath: repoPath,
                    remoteURL: normalized,
                    owner: owner.isEmpty ? "local" : owner,
                    saddled: saddled,
                    hasReadme: checkFile(at: repoPath, candidates: [
                        "README.md", "README", "README.rst", "README.txt", "README.markdown",
                    ]),
                    hasGitignore: FS.exists("\(repoPath)/.gitignore"),
                    hasMakefile: checkFile(at: repoPath, candidates: [
                        "Makefile", "makefile", "GNUmakefile",
                    ]),
                    hasLicense: checkFile(at: repoPath, candidates: [
                        "LICENSE", "LICENSE.md", "LICENSE.txt",
                        "LICENCE", "LICENCE.md", "LICENCE.txt", "COPYING",
                    ]),
                    hasHealthHook: hasHealthHook,
                    hookPassed: hookPassed
                )

                scanLock.lock()
                scanned += 1
                spinner.status = styled("[\(scanned)/\(repoCount)]", .dim)
                scanLock.unlock()
            }
        }

        spinner.stop()

        let repos = applyFilters(Array(results))

        if !repos.isEmpty {
            printHealthTable(repos, mountDir: devDir)
        } else {
            print()
            print()
            print(styled("No repos matched the given filters.", .dim))
        }

        printFilterLine(repos: repos)
    }

    // MARK: - File Checks

    private func checkFile(at root: String, candidates: [String]) -> Bool {
        candidates.contains { FS.exists("\(root)/\($0)") }
    }

    // MARK: - Filtering

    private var activeFilters: [String] {
        var filters: [String] = []
        if equipped && !stray { filters.append("equipped") }
        if stray && !equipped { filters.append("stray") }
        if healthy && !unhealthy { filters.append("healthy") }
        if unhealthy && !healthy { filters.append("unhealthy") }
        if let owner { filters.append("owner: \(owner)") }
        if filters.isEmpty { filters.append("all") }
        return filters
    }

    private func printFilterLine(repos: [HealthInfo]) {
        let filters = activeFilters
        let filterText = styled(filters.joined(separator: ", "), .cyan)
        print()
        print(styled("  \u{25BC} Filters applied:", .dim) + " " + filterText + " " + styled("(\(repos.count) repos)", .darkGray))
    }

    private func applyFilters(_ repos: [HealthInfo]) -> [HealthInfo] {
        repos.filter { repo in
            if equipped != stray {
                if equipped && !repo.saddled { return false }
                if stray && repo.saddled { return false }
            }
            if healthy != unhealthy {
                if healthy && !repo.isHealthy { return false }
                if unhealthy && repo.isHealthy { return false }
            }
            if let owner {
                if repo.owner.lowercased() != owner.lowercased() { return false }
            }
            return true
        }
    }

    // MARK: - Display

    private func printHealthTable(_ repos: [HealthInfo], mountDir: String) {
        let termWidth = terminalWidth()
        let mountLabel = FS.shortenPath(mountDir)

        let table = TrafficLightTable(segments: [
            .indicators([
                Indicator("equipped", color: .custom(RGB(hex: "4A9EC2").fg)),
                Indicator("stray", color: .custom(RGB(hex: "C85A6A").fg)),
            ]),
            .column(TextColumn("Local Repository (\(mountLabel))", sizing: .auto())),
            .indicators([
                Indicator("readme", color: .custom(RGB(hex: "5EC269").fg)),
                Indicator("gitignore", color: .custom(RGB(hex: "61AFEF").fg)),
                Indicator("makefile", color: .custom(RGB(hex: "D19A66").fg)),
                Indicator("license", color: .custom(RGB(hex: "E5C07B").fg)),
                Indicator("installed", color: .custom(RGB(hex: "50C878").fg)),
            ]),
            .column(TextColumn("Missing", sizing: .flexible(minWidth: 10))),
        ])

        let sorted = repos.sorted { $0.relativePath.lowercased() < $1.relativePath.lowercased() }
        let rows = sorted.map { buildRow(repo: $0) }
        let counts = legendCounts(repos: repos)

        print(table.render(rows: rows, counts: counts, terminalWidth: termWidth), terminator: "")
    }

    private func buildRow(repo: HealthInfo) -> TrafficLightRow {
        let identityStates: [IndicatorState] = [
            repo.saddled ? .on : .off,
            repo.isStray ? .on : .off,
        ]

        let healthStates: [IndicatorState] = [
            repo.hasReadme ? .on : .off,
            repo.hasGitignore ? .on : .off,
            repo.hasMakefile ? .on : .off,
            repo.hasLicense ? .on : .off,
            repo.hasHealthHook && repo.hookPassed ? .on : .off,
        ]

        let pathCol = stylePath(repo)
        let missing = repo.missingFiles
        let missingCol = missing.isEmpty
            ? styled("\u{2014}", .dim)
            : styled(missing.joined(separator: ", "), .dim)

        return TrafficLightRow(
            indicators: [identityStates, healthStates],
            values: [pathCol, missingCol]
        )
    }

    private func stylePath(_ repo: HealthInfo) -> String {
        styledRepoPath(repo.relativePath)
    }

    private func legendCounts(repos: [HealthInfo]) -> [[Int]] {
        [
            [
                repos.filter(\.saddled).count,
                repos.filter(\.isStray).count,
            ],
            [
                repos.filter(\.hasReadme).count,
                repos.filter(\.hasGitignore).count,
                repos.filter(\.hasMakefile).count,
                repos.filter(\.hasLicense).count,
                repos.filter { $0.hasHealthHook && $0.hookPassed }.count,
            ],
        ]
    }
}
