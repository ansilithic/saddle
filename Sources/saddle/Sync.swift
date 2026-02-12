import CLICore
import Foundation

struct Sync {

    private static let colPadding = 4

    struct RowResult {
        let url: String
        let name: String
        let outcome: SyncOutcome
        let hookResult: HookResult?
    }

    static func syncDeclaredRepos(_ urls: [String], mount: String, dryRun: Bool) {
        let devDir = mount
        var results = SyncResult()
        var rows: [RowResult] = []

        let discoveredPaths = FS.findRepos(in: devDir)
        var urlToPath: [String: String] = [:]
        for repoPath in discoveredPaths {
            let (output, rc) = Exec.git("remote", "get-url", "origin", at: repoPath)
            if rc == 0, !output.isEmpty {
                urlToPath[URLHelpers.normalize(output)] = repoPath
            }
        }

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

        let missingIndices = entries.indices.filter { !entries[$0].isExisting }
        let existingIndices = entries.indices.filter { entries[$0].isExisting }

        var outcomes: [SyncOutcome?] = Array(repeating: nil, count: entries.count)

        // Wrangling — clone missing repos

        printPhase("Wrangling", "cloning missing repos")

        if missingIndices.isEmpty {
            print("    \(styled("all repos present", .dim))")
        } else {
            for (phaseIdx, entryIdx) in missingIndices.enumerated() {
                let entry = entries[entryIdx]
                print("    \(styled("[\(phaseIdx + 1)/\(missingIndices.count)]", .dim)) \(entry.name)", terminator: "")
                fflush(stdout)

                let clonePath = "\(devDir)/\(entry.name)"
                let outcome: SyncOutcome
                if dryRun {
                    outcome = .wouldSync
                } else {
                    let parent = (clonePath as NSString).deletingLastPathComponent
                    if !FS.isDirectory(parent) { _ = FS.createDirectory(parent) }
                    let cloneURL = URLHelpers.sshURL(from: entry.url)
                    let (_, exitCode) = Exec.run("/usr/bin/git", args: ["clone", cloneURL, clonePath], env: ["GIT_TERMINAL_PROMPT": "0"])
                    if exitCode == 0 {
                        outcome = .synced
                        entries[entryIdx].path = clonePath
                    } else {
                        outcome = .failed("clone failed")
                    }
                }

                outcomes[entryIdx] = outcome
                let (statusText, statusColor) = statusLabel(outcome)
                print(" \(styled(statusText, statusColor))")

                if case .failed(let reason) = outcome {
                    Log.error("\(reason) for \(entry.name) (\(entry.url))")
                }
                results.record(outcome, name: entry.name)
            }
        }

        // Grooming — pull latest changes

        printPhase("Grooming", "pulling latest changes")

        if existingIndices.isEmpty {
            print("    \(styled("no existing repos", .dim))")
        } else {
            for (phaseIdx, entryIdx) in existingIndices.enumerated() {
                let entry = entries[entryIdx]
                let existingPath = entry.path!

                print("    \(styled("[\(phaseIdx + 1)/\(existingIndices.count)]", .dim)) \(entry.name)", terminator: "")
                fflush(stdout)

                let outcome: SyncOutcome
                let (statusOutput, _) = Exec.git("status", "--porcelain", at: existingPath)
                if !statusOutput.isEmpty {
                    outcome = .skipped
                } else if dryRun {
                    outcome = .wouldSync
                } else {
                    let (_, fetchExit) = Exec.git("fetch", at: existingPath)
                    if fetchExit != 0 {
                        outcome = .failed("fetch failed")
                        entries[entryIdx].path = nil
                    } else {
                        let (behindOutput, _) = Exec.git("rev-list", "--count", "HEAD..@{u}", at: existingPath)
                        let behind = Int(behindOutput) ?? 0
                        if behind == 0 {
                            outcome = .unchanged
                        } else {
                            let (_, pullExit) = Exec.git("pull", "--ff-only", at: existingPath)
                            if pullExit == 0 {
                                outcome = .synced
                            } else {
                                outcome = .failed("pull failed")
                                entries[entryIdx].path = nil
                            }
                        }
                    }
                }

                outcomes[entryIdx] = outcome
                let (statusText, statusColor) = statusLabel(outcome)
                print(" \(styled(statusText, statusColor))")

                if case .failed(let reason) = outcome {
                    Log.error("\(reason) for \(entry.name) (\(entry.url))")
                }
                results.record(outcome, name: entry.name)
            }
        }

        // Spurring — run hooks

        printPhase("Spurring", "running hooks")

        var hookResults: [Int: HookResult] = [:]
        let hookIndices: [Int]
        if dryRun {
            hookIndices = entries.indices.filter { findHook(for: entries[$0].url) != nil }
        } else {
            hookIndices = entries.indices.filter { entries[$0].path != nil && findHook(for: entries[$0].url) != nil }
        }

        if hookIndices.isEmpty {
            print("    \(styled("no hooks configured", .dim))")
        } else {
            for (phaseIdx, entryIdx) in hookIndices.enumerated() {
                let entry = entries[entryIdx]
                let hookName = URLHelpers.hookName(from: entry.url)

                print("    \(styled("[\(phaseIdx + 1)/\(hookIndices.count)]", .dim)) \(entry.name)", terminator: "")
                fflush(stdout)

                if dryRun {
                    hookResults[entryIdx] = .pending
                    print(" \(styled(hookName, .dim))")
                } else {
                    let spinner = BrailleSpinner()
                    spinner.start()
                    let result = runHook(for: entry.url, at: entry.path!)
                    spinner.stop()

                    // Reprint prefix since spinner clears the line
                    print("    \(styled("[\(phaseIdx + 1)/\(hookIndices.count)]", .dim)) \(entry.name)", terminator: "")

                    if let result = result {
                        hookResults[entryIdx] = result
                        if case .ran(_, let exitCode, _) = result {
                            let status = exitCode == 0 ? styled("ok", .green) : styled("exit \(exitCode)", .red)
                            print(" \(status)")
                        } else {
                            print()
                        }
                    } else {
                        print()
                    }
                }
            }
        }

        for (i, entry) in entries.enumerated() {
            let outcome = outcomes[i] ?? .unchanged
            let hookResult = hookResults[i]
            rows.append(RowResult(url: entry.url, name: entry.name, outcome: outcome, hookResult: hookResult))
        }

        let statusValues = ["synced", "up to date", "skipped (dirty)", "fetch failed", "pull failed", "clone failed", "would sync"]
        let hookEntries: [String] = rows.compactMap {
            if case .ran(let n, let c, _) = $0.hookResult { return "\(n) \(c == 0 ? "ok" : "exit \(c)")" }
            if case .pending = $0.hookResult { return URLHelpers.hookName(from: $0.url) }
            return nil
        }
        let colName = max("Repo".count, rows.map(\.name.count).max() ?? 0) + colPadding
        let colStatus = max("Local Status".count, statusValues.map(\.count).max() ?? 0) + colPadding
        let colHook = max("Hook".count, hookEntries.map(\.count).max() ?? 0) + colPadding

        printHeader(colName: colName, colStatus: colStatus, colHook: colHook)
        for row in rows {
            printRow(row.name, row.outcome, row.hookResult, for: row.url, colName: colName, colStatus: colStatus, colHook: colHook)
        }
        printSyncSummary(results, dryRun: dryRun)
    }

    private static func printPhase(_ name: String, _ description: String) {
        print()
        print("  \(styled("\(name)\u{2026}", .bold))  \(styled(description, .dim))")
        print()
    }

    // MARK: - Hooks

    enum HookResult {
        case pending
        case ran(name: String, exitCode: Int32, logPath: String)
    }

    static func findHook(for url: String) -> String? {
        let hookName = URLHelpers.hookName(from: url)
        let hookPath = "\(Config.hooksDir)/\(hookName)"
        guard FS.exists(hookPath) && FS.isExecutable(hookPath) else { return nil }
        return hookPath
    }

    @discardableResult
    private static func runHook(for url: String, at repoPath: String) -> HookResult? {
        guard findHook(for: url) != nil else { return nil }
        let hookName = URLHelpers.hookName(from: url)
        let hookPath = "\(Config.hooksDir)/\(hookName)"
        let (output, exitCode) = Exec.run(hookPath, args: [], cwd: repoPath)

        let logsDir = Config.hookLogsDir
        if !FS.isDirectory(logsDir) { _ = FS.createDirectory(logsDir) }
        let logName = hookName.replacingOccurrences(of: ".sh", with: ".log")
        let logPath = "\(logsDir)/\(logName)"
        let timestamp = DateFormatting.iso8601.string(from: Date())
        let logContent = "[\(timestamp)] exit \(exitCode)\n\(output)\n"
        _ = FS.writeFile(logPath, contents: logContent)

        if exitCode != 0 {
            Log.error("Hook \(hookName) failed (exit \(exitCode)) for \(URLHelpers.repoName(from: url))")
        }

        return .ran(name: hookName, exitCode: exitCode, logPath: logPath)
    }

    // MARK: - Output

    private static func printHeader(colName: Int, colStatus: Int, colHook: Int) {
        print()
        let header = "     "
            + "Repo".padded(to: colName)
            + "Local Status".padded(to: colStatus)
            + "Hook".padded(to: colHook)
            + "Log"
        print(styled(header, .dim))
        let totalWidth = 5 + colName + colStatus + colHook + 20
        print(styled("\u{2500}".repeating(totalWidth), .dim))
    }

    private static func statusLabel(_ outcome: SyncOutcome) -> (String, Color) {
        switch outcome {
        case .synced:         return ("synced", .green)
        case .unchanged:      return ("up to date", .gray)
        case .skipped:        return ("skipped (dirty)", .yellow)
        case .failed(let r):  return (r.isEmpty ? "failed" : r, .red)
        case .wouldSync:      return ("would sync", .cyan)
        }
    }

    private static func outcomeIndicator(_ outcome: SyncOutcome) -> String {
        switch outcome {
        case .failed:  return styled("\u{2717}", .red)
        case .skipped: return styled("\u{2713}", .yellow)
        default:       return styled("\u{2713}", .green)
        }
    }

    private static func printRow(_ name: String, _ outcome: SyncOutcome, _ hookResult: HookResult?, for url: String, colName: Int, colStatus: Int, colHook: Int) {
        let indicator = outcomeIndicator(outcome)
        let (statusText, color) = statusLabel(outcome)
        let paddedName = name.padded(to: colName)
        let paddedStatus = styled(statusText, color).padded(to: colStatus)

        let hookCol: String
        let logCol: String
        switch hookResult {
        case .pending:
            let hookName = URLHelpers.hookName(from: url)
            hookCol = styled(hookName, .dim).padded(to: colHook)
            logCol = ""
        case .ran(let hookName, let exitCode, let logPath):
            let status = exitCode == 0 ? styled("ok", .green) : styled("exit \(exitCode)", .red)
            hookCol = (styled(hookName, .dim) + " " + status).padded(to: colHook)
            logCol = styled("\u{2192} ", .dim) + styled(FS.shortenPath(logPath), .darkGray)
        case nil:
            hookCol = styled("\u{2014}", .dim).padded(to: colHook)
            logCol = ""
        }

        print("  \(indicator)  \(paddedName)\(paddedStatus)\(hookCol)\(logCol)")
    }

    private static func printSyncSummary(_ results: SyncResult, dryRun: Bool) {
        print()
        var parts: [String] = []
        if dryRun {
            if results.wouldSync > 0 { parts.append(styled("\(results.wouldSync) would sync", .cyan)) }
            if results.unchanged > 0 { parts.append(styled("\(results.unchanged) unchanged", .gray)) }
            if results.skipped > 0 { parts.append(styled("\(results.skipped) skipped", .yellow)) }
        } else {
            if results.synced > 0 { parts.append(styled("\(results.synced) synced", .green)) }
            if results.unchanged > 0 { parts.append(styled("\(results.unchanged) unchanged", .gray)) }
            if results.skipped > 0 { parts.append(styled("\(results.skipped) skipped", .yellow)) }
            if results.failed > 0 { parts.append(styled("\(results.failed) failed", .red)) }
        }
        Output.printSummary(parts)
    }
}
