import CLICore
import Foundation

struct Sync {

    struct RowResult {
        let relativePath: String
        let outcome: SyncOutcome
        let hookResult: HookResult?
        let duration: TimeInterval
    }

    static func syncDeclaredRepos(_ urls: [String], mount: String, cloneProtocol: Manifest.CloneProtocol = .ssh, runHooks: Bool = true, forceHooks: Bool = false) {
        let devDir = mount
        nonisolated(unsafe) var results = SyncResult()
        var rows: [RowResult] = []

        // Scan for existing repos

        print()

        let discoveredPaths = FS.findRepos(in: devDir)
        let trackedNormalized = Set(urls.map { URLHelpers.normalize($0) })

        let scanSpinner = ProgressSpinner()
        let scanCount = discoveredPaths.count
        scanSpinner.label = styled("Scanning\u{2026}", .bold) + "  " + styled(FS.shortenPath(devDir), .dim)
        scanSpinner.start()

        let scanLock = NSLock()
        nonisolated(unsafe) var urlToPath: [String: String] = [:]
        nonisolated(unsafe) var untrackedCount = 0
        nonisolated(unsafe) var scannedCount = 0

        DispatchQueue.concurrentPerform(iterations: scanCount) { i in
            let repoPath = discoveredPaths[i]

            let (output, rc) = Exec.git("config", "remote.origin.url", at: repoPath)

            scanLock.lock()
            scannedCount += 1
            if rc == 0, !output.isEmpty {
                let normalized = URLHelpers.normalize(output)
                urlToPath[normalized] = repoPath
                if !trackedNormalized.contains(normalized) {
                    untrackedCount += 1
                }
            } else {
                untrackedCount += 1
            }
            scanLock.unlock()
        }

        let scanSummary = untrackedCount == 0
            ? "\(discoveredPaths.count) found, all tracked"
            : "\(discoveredPaths.count) found, \(untrackedCount) untracked"
        scanSpinner.summary = "  " + styled(scanSummary, .dim)
        scanSpinner.stop()

        // Build entries

        struct RepoEntry {
            let url: String
            let name: String
            var path: String?
            let isExisting: Bool
        }

        let entries: [RepoEntry] = urls.map { url in
            let name = URLHelpers.repoName(from: url)
            let normalized = URLHelpers.normalize(url)
            let path = urlToPath[normalized]
            return RepoEntry(url: url, name: name, path: path, isExisting: path != nil)
        }

        // Reachability check for non-standard hosts

        let wellKnownHosts: Set<String> = ["github.com", "gitlab.com"]
        let customHosts = Set(entries.map { URLHelpers.host(from: $0.url) }).subtracting(wellKnownHosts)
        nonisolated(unsafe) var unreachableHosts: Set<String> = []
        if !customHosts.isEmpty {
            let reachLock = NSLock()
            let sortedHosts = customHosts.sorted()
            var reachResults = Array(repeating: true, count: sortedHosts.count)
            reachResults.withUnsafeMutableBufferPointer { buf in
                nonisolated(unsafe) let buffer = buf
                DispatchQueue.concurrentPerform(iterations: sortedHosts.count) { i in
                    let host = sortedHosts[i]
                    let http = ForgeHTTP(baseURL: "https://\(host)/api/v4", acceptHeader: "application/json")
                    let ok = http.reachable(timeout: 3)
                    if !ok {
                        buffer[i] = false
                        reachLock.lock()
                        unreachableHosts.insert(host)
                        reachLock.unlock()
                    }
                }
            }
        }

        // Concurrent clone/pull + hooks

        print()

        let spinner = ProgressSpinner()
        let entryCount = entries.count
        let lock = NSLock()
        nonisolated(unsafe) var completed = 0
        nonisolated(unsafe) var okCount = 0
        nonisolated(unsafe) var failedCount = 0
        var rowBuffer = Array(repeating: RowResult(relativePath: "", outcome: .unchanged, hookResult: nil, duration: 0), count: entryCount)

        spinner.label = styled("Wrangling\u{2026}", .bold) + "  " + styled("\(entryCount) repos", .dim)
        spinner.status = styled("[0/\(entryCount)]", .dim)
        spinner.start()

        rowBuffer.withUnsafeMutableBufferPointer { buf in
            nonisolated(unsafe) let buffer = buf
            DispatchQueue.concurrentPerform(iterations: entryCount) { i in
                let entry = entries[i]
                let relativePath = URLHelpers.pathAfterHost(from: entry.url)
                let startTime = CFAbsoluteTimeGetCurrent()

                spinner.activate("\(i)", name: relativePath)

                // Clone or pull
                let entryHost = URLHelpers.host(from: entry.url)
                let hostUnreachable = unreachableHosts.contains(entryHost)

                let outcome: SyncOutcome
                var resolvedPath = entry.path
                if hostUnreachable {
                    outcome = .failed("\(entryHost) unreachable")
                } else if !entry.isExisting {
                    let clonePath = "\(devDir)/\(URLHelpers.pathAfterHost(from: entry.url))"
                    outcome = cloneRepo(url: entry.url, path: clonePath, cloneProtocol: cloneProtocol)
                    if case .synced = outcome {
                        resolvedPath = clonePath
                    }
                } else if let existingPath = entry.path {
                    outcome = pullRepo(path: existingPath)
                    if case .failed = outcome, !forceHooks {
                        resolvedPath = nil
                    }
                } else {
                    outcome = .unchanged
                }

                // Run hook
                var hookResult: HookResult? = nil
                if runHooks, let repoPath = resolvedPath, HookResolver.hasHook(for: entry.url) {
                    let isSynced: Bool
                    if case .synced = outcome { isSynced = true } else { isSynced = false }
                    let isNewClone = !entry.isExisting && isSynced
                    let lifecycle: Lifecycle = isNewClone ? .install : .update
                    if let resolution = HookResolver.resolve(for: entry.url, lifecycle: lifecycle) {
                        hookResult = HookResolver.execute(resolution, at: repoPath)
                    }
                }

                let duration = CFAbsoluteTimeGetCurrent() - startTime

                // Record (synchronized)
                lock.lock()
                completed += 1
                results.record(outcome, name: entry.name)
                if case .failed(let reason) = outcome {
                    failedCount += 1
                    Log.error("\(reason) for \(entry.name) (\(entry.url))")
                    spinner.fail("\(i)", reason: reason)
                } else {
                    okCount += 1
                    spinner.complete("\(i)")
                }
                let okStr = okCount > 0 ? "  " + styled("\(okCount) ok", .green) : ""
                let failStr = failedCount > 0 ? "  " + styled("\(failedCount) failed", .red) : ""
                spinner.status = styled("[\(completed)/\(entryCount)]", .dim) + okStr + failStr
                lock.unlock()

                buffer[i] = RowResult(relativePath: relativePath, outcome: outcome, hookResult: hookResult, duration: duration)
            }
        }

        rows = rowBuffer

        let syncedLabel = results.synced > 0 ? "\(results.synced) synced" : ""
        let unchangedLabel = results.unchanged > 0 ? "\(results.unchanged) unchanged" : ""
        let skippedLabel = results.skipped > 0 ? "\(results.skipped) skipped" : ""
        let failedLabel = results.failed > 0 ? "\(results.failed) failed" : ""
        let wrangleSummary = [syncedLabel, unchangedLabel, skippedLabel, failedLabel].filter { !$0.isEmpty }
        spinner.summary = "  " + styled(wrangleSummary.joined(separator: ", "), .dim)
        spinner.stop()

        // Render table

        let sortedRows = rows.sorted { $0.relativePath.lowercased() < $1.relativePath.lowercased() }

        let table = TrafficLightTable(segments: [
            .indicators([
                Indicator("synced", color: .blue),
                Indicator("skipped (dirty)", color: .yellow),
                Indicator("sync failed", color: .red),
                Indicator("hooked", color: .green),
            ]),
            .column(TextColumn("Repo", sizing: .auto())),
            .column(TextColumn("Time", sizing: .auto())),
        ])

        let tableRows = sortedRows.map { row -> TrafficLightRow in
            let isSynced: Bool
            if case .synced = row.outcome { isSynced = true } else { isSynced = false }
            let isDirty: Bool
            if case .skipped = row.outcome { isDirty = true } else { isDirty = false }
            let isFailed: Bool
            if case .failed = row.outcome { isFailed = true } else { isFailed = false }
            let isHooked: Bool
            if case .ran = row.hookResult { isHooked = true } else { isHooked = false }

            let timeCol = styledDuration(row.duration)

            return TrafficLightRow(
                indicators: [[
                    isSynced ? .on : .off,
                    isDirty ? .on : .off,
                    isFailed ? .on : .off,
                    isHooked ? .on : .off,
                ]],
                values: [styledRepoPath(row.relativePath), timeCol]
            )
        }

        let hookedCount = rows.filter { if case .ran = $0.hookResult { return true } else { return false } }.count
        let counts: [[Int]] = [[results.synced, results.skipped, results.failed, hookedCount]]
        print(table.render(rows: tableRows, counts: counts, terminalWidth: terminalWidth()), terminator: "")
        printSyncSummary(results)
    }

    // MARK: - Sync Operations

    private static func cloneRepo(url: String, path: String, cloneProtocol: Manifest.CloneProtocol) -> SyncOutcome {
        let parent = (path as NSString).deletingLastPathComponent
        if !FS.isDirectory(parent) { _ = FS.createDirectory(parent) }
        let cloneURL = URLHelpers.cloneURL(from: url, protocol: cloneProtocol)
        let (output, exitCode) = Exec.run("/usr/bin/git", args: ["clone", cloneURL, path], env: ["GIT_TERMINAL_PROMPT": "0"], timeout: 60)
        return exitCode == 0 ? .synced : .failed("clone failed: \(lastMeaningfulLine(output))")
    }

    private static func pullRepo(path: String) -> SyncOutcome {
        let (statusOutput, _) = Exec.git("status", "--porcelain", at: path)
        if !statusOutput.isEmpty { return .skipped }

        let (fetchOutput, fetchExit) = Exec.git("fetch", at: path, timeout: 30)
        if fetchExit != 0 { return .failed("fetch failed: \(lastMeaningfulLine(fetchOutput))") }

        let (behindOutput, _) = Exec.git("rev-list", "--count", "HEAD..@{u}", at: path)
        let behind = Int(behindOutput) ?? 0
        if behind == 0 { return .unchanged }

        let (pullOutput, pullExit) = Exec.git("pull", "--ff-only", at: path, timeout: 60)
        return pullExit == 0 ? .synced : .failed("pull failed: \(lastMeaningfulLine(pullOutput))")
    }

    private static func lastMeaningfulLine(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Formatting

    private static func styledRepoPath(_ path: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else {
            return styled(path, .bold)
        }
        let before = String(path[path.startIndex...lastSlash])
        let name = String(path[path.index(after: lastSlash)...])
        return styled(before, .darkGray) + styled(name, .bold)
    }

    private static func styledDuration(_ seconds: TimeInterval) -> String {
        let text: String
        if seconds < 60 {
            text = String(format: "%.1fs", seconds)
        } else {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            text = "\(m)m\(s)s"
        }
        if seconds < 2 { return styled(text, .dim) }
        if seconds < 10 { return styled(text, .yellow) }
        return styled(text, .red)
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

        if !results.failures.isEmpty {
            print()
            for failure in results.failures {
                print("  " + styled("\u{2716}", .red) + " " + styled(failure.name, .bold) + " " + styled(failure.message, .dim))
            }
        }
    }
}
