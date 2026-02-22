import CLICore
import Foundation

struct Sync {

    struct RowResult {
        let relativePath: String
        let outcome: SyncOutcome
        let hookResult: HookResult?
    }

    static func syncDeclaredRepos(_ urls: [String], mount: String, cloneProtocol: Manifest.CloneProtocol = .ssh, runHooks: Bool = true) {
        let devDir = mount
        var results = SyncResult()
        var rows: [RowResult] = []

        // Scan for existing repos

        print()
        print("  \(styled("Scanning\u{2026}", .bold))  \(styled(FS.shortenPath(devDir), .dim))")
        fflush(stdout)

        let discoveredPaths = FS.findRepos(in: devDir)
        let trackedNormalized = Set(urls.map { URLHelpers.normalize($0) })

        let scanSpinner = ProgressSpinner()
        scanSpinner.label = styled("\(discoveredPaths.count) found\u{2026}", .dim)
        scanSpinner.start()

        var urlToPath: [String: String] = [:]
        var untrackedCount = 0
        for repoPath in discoveredPaths {
            let (output, rc) = Exec.git("remote", "get-url", "origin", at: repoPath)
            if rc == 0, !output.isEmpty {
                let normalized = URLHelpers.normalize(output)
                urlToPath[normalized] = repoPath
                if !trackedNormalized.contains(normalized) {
                    untrackedCount += 1
                }
            } else {
                untrackedCount += 1
            }
            scanSpinner.label = styled("\(discoveredPaths.count) found, \(untrackedCount) untracked", .dim)
        }

        scanSpinner.stop()

        if untrackedCount == 0 {
            print("  \(styled("\(discoveredPaths.count) found, all tracked", .dim))")
        } else {
            print("  \(styled("\(discoveredPaths.count) found, \(untrackedCount) untracked", .dim))")
        }

        // Build entries

        struct RepoEntry {
            let url: String
            let name: String
            var path: String?
            let isExisting: Bool
        }

        var entries: [RepoEntry] = urls.map { url in
            let name = URLHelpers.repoName(from: url)
            let normalized = URLHelpers.normalize(url)
            let path = urlToPath[normalized]
            return RepoEntry(url: url, name: name, path: path, isExisting: path != nil)
        }

        // Single-pass: clone/pull + hooks

        print()
        print("  \(styled("Wrangling\u{2026}", .bold))  \(styled("\(entries.count) repos", .dim))")

        let spinner = ProgressSpinner()
        spinner.start()

        for i in entries.indices {
            let entry = entries[i]
            let relativePath = URLHelpers.pathAfterHost(from: entry.url)
            spinner.label = styled("[\(i + 1)/\(entries.count)]", .dim) + " " + styledRepoPath(relativePath) + styled("\u{2026}", .dim)

            // Clone or pull
            let outcome: SyncOutcome
            if !entry.isExisting {
                let clonePath = "\(devDir)/\(URLHelpers.pathAfterHost(from: entry.url))"
                outcome = cloneRepo(url: entry.url, path: clonePath, cloneProtocol: cloneProtocol)
                if case .synced = outcome {
                    entries[i].path = clonePath
                }
            } else if let existingPath = entry.path {
                outcome = pullRepo(path: existingPath)
                if case .failed = outcome {
                    entries[i].path = nil
                }
            } else {
                outcome = .unchanged
            }

            // Run hook
            var hookResult: HookResult? = nil
            if runHooks, let repoPath = entries[i].path, HookResolver.hasHook(for: entry.url) {
                let isSynced: Bool
                if case .synced = outcome { isSynced = true } else { isSynced = false }
                let isNewClone = !entry.isExisting && isSynced
                let lifecycle: Lifecycle = isNewClone ? .install : .update
                if let resolution = HookResolver.resolve(for: entry.url, lifecycle: lifecycle) {
                    hookResult = HookResolver.execute(resolution, at: repoPath)
                }
            }

            // Record
            results.record(outcome, name: entry.name)
            if case .failed(let reason) = outcome {
                Log.error("\(reason) for \(entry.name) (\(entry.url))")
            }
            rows.append(RowResult(relativePath: relativePath, outcome: outcome, hookResult: hookResult))
        }

        spinner.stop()

        // Render table

        let sortedRows = rows.sorted { $0.relativePath.lowercased() < $1.relativePath.lowercased() }

        let table = TrafficLightTable(segments: [
            .indicators([
                Indicator("synced", color: .blue),
                Indicator("skipped (dirty)", color: .yellow),
                Indicator("sync failed", color: .red),
            ]),
            .column(TextColumn("Repo", sizing: .auto())),
            .column(TextColumn("Hook", sizing: .auto())),
            .column(TextColumn("Log", sizing: .flexible(minWidth: 0))),
        ])

        let tableRows = sortedRows.map { row -> TrafficLightRow in
            let isSynced: Bool
            if case .synced = row.outcome { isSynced = true } else { isSynced = false }
            let isDirty: Bool
            if case .skipped = row.outcome { isDirty = true } else { isDirty = false }
            let isFailed: Bool
            if case .failed = row.outcome { isFailed = true } else { isFailed = false }

            let hookCol: String
            let logCol: String
            switch row.hookResult {
            case .ran(let hookName, let exitCode, let logPath):
                let status = exitCode == 0 ? styled("ok", .green) : styled("exit \(exitCode)", .red)
                hookCol = styled(hookName, .dim) + " " + status
                logCol = styled(FS.shortenPath(logPath), .darkGray)
            case .pending, nil:
                hookCol = styled("\u{2014}", .dim)
                logCol = ""
            }

            return TrafficLightRow(
                indicators: [[
                    isSynced ? .on : .off,
                    isDirty ? .on : .off,
                    isFailed ? .on : .off,
                ]],
                values: [styledRepoPath(row.relativePath), hookCol, logCol]
            )
        }

        let counts: [[Int]] = [[results.synced, results.skipped, results.failed]]
        print(table.render(rows: tableRows, counts: counts, terminalWidth: terminalWidth()), terminator: "")
        printSyncSummary(results)
    }

    // MARK: - Sync Operations

    private static func cloneRepo(url: String, path: String, cloneProtocol: Manifest.CloneProtocol) -> SyncOutcome {
        let parent = (path as NSString).deletingLastPathComponent
        if !FS.isDirectory(parent) { _ = FS.createDirectory(parent) }
        let cloneURL = URLHelpers.cloneURL(from: url, protocol: cloneProtocol)
        let (_, exitCode) = Exec.run("/usr/bin/git", args: ["clone", cloneURL, path], env: ["GIT_TERMINAL_PROMPT": "0"])
        return exitCode == 0 ? .synced : .failed("clone failed")
    }

    private static func pullRepo(path: String) -> SyncOutcome {
        let (statusOutput, _) = Exec.git("status", "--porcelain", at: path)
        if !statusOutput.isEmpty { return .skipped }

        let (_, fetchExit) = Exec.git("fetch", at: path)
        if fetchExit != 0 { return .failed("fetch failed") }

        let (behindOutput, _) = Exec.git("rev-list", "--count", "HEAD..@{u}", at: path)
        let behind = Int(behindOutput) ?? 0
        if behind == 0 { return .unchanged }

        let (_, pullExit) = Exec.git("pull", "--ff-only", at: path)
        return pullExit == 0 ? .synced : .failed("pull failed")
    }

    // MARK: - Formatting

    private static func styledRepoPath(_ path: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else {
            return styled(path, .custom(RGB(hex: "39FF14").fg))
        }
        let before = String(path[path.startIndex...lastSlash])
        let name = String(path[path.index(after: lastSlash)...])
        return styled(before, .darkGray) + styled(name, .custom(RGB(hex: "39FF14").fg))
    }

    // MARK: - Output

    private static func printSyncSummary(_ results: SyncResult) {
        print()
        var parts: [String] = []
        if results.synced > 0 { parts.append(styled("\(results.synced) synced", .blue)) }
        if results.unchanged > 0 { parts.append(styled("\(results.unchanged) unchanged", .gray)) }
        if results.skipped > 0 { parts.append(styled("\(results.skipped) skipped", .yellow)) }
        if results.failed > 0 { parts.append(styled("\(results.failed) failed", .red)) }
        Output.printSummary(parts)
    }
}
