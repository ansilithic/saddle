import CLICore
import Foundation

struct Sync {

    /// Why a row's hook ran (or didn't). Surfaces in the rightmost trigger
    /// column so the user can see at a glance: "this ran because its source
    /// changed" vs "this ran because an upstream dep changed."
    enum Trigger {
        case noOp                                   // nothing changed, hook didn't run
        case ownDrift                               // own source drifted, hook ran
        case cascade(from: [String])                // upstream(s) ran, my hook also ran
        case forced                                 // --force-hooks
        case install                                // first-time clone
        case skippedDirty                           // working tree dirty
        case syncFailed                             // clone/pull failed
        case hookFailed(summary: String)
        case hookTimedOut(ranSeconds: Double, threshold: Double, median: Double)
    }

    struct RowResult {
        let relativePath: String
        let url: String
        let normalized: String
        let level: Int
        let outcome: SyncOutcome
        let hookResult: HookResult?
        let duration: TimeInterval
        let trigger: Trigger
    }

    static func syncDeclaredRepos(
        _ urls: [String],
        mount: String,
        cloneProtocol: Manifest.CloneProtocol = .ssh,
        manifestDeps: [String: [String]] = [:],
        runHooks: Bool = true,
        forceHooks: Bool = false
    ) {
        let devDir = mount
        nonisolated(unsafe) var results = SyncResult()

        // ── Scan local repos ────────────────────────────────────────

        print()

        let discoveredPaths = FS.findRepos(in: devDir)
        let trackedNormalized = Set(urls.map { URLHelpers.normalize($0) })

        let scanSpinner = ProgressSpinner()
        let scanCount = discoveredPaths.count
        scanSpinner.label = styled("Scanning\u{2026}", .bold) + "  " + styled(FS.shortenPath(devDir), .dim)
        scanSpinner.status = styled("[0/\(scanCount)]", .dim)
        scanSpinner.start()

        let scanLock = NSLock()
        nonisolated(unsafe) var urlToPath: [String: String] = [:]
        nonisolated(unsafe) var untrackedCount = 0
        nonisolated(unsafe) var scanned = 0

        DispatchQueue.concurrentPerform(iterations: scanCount) { i in
            let repoPath = discoveredPaths[i]
            let (output, rc) = Exec.git("config", "remote.origin.url", at: repoPath)
            scanLock.lock()
            if rc == 0, !output.isEmpty {
                let normalized = URLHelpers.normalize(output)
                urlToPath[normalized] = repoPath
                if !trackedNormalized.contains(normalized) {
                    untrackedCount += 1
                }
            } else {
                untrackedCount += 1
            }
            scanned += 1
            scanSpinner.status = styled("[\(scanned)/\(scanCount)]", .dim)
            scanLock.unlock()
        }

        let scanSummary = untrackedCount == 0
            ? "\(discoveredPaths.count) found, all tracked"
            : "\(discoveredPaths.count) found, \(untrackedCount) untracked"
        scanSpinner.summary = "  " + styled(scanSummary, .dim)
        scanSpinner.stop()

        // ── Build entries ───────────────────────────────────────────

        struct RepoEntry {
            let url: String
            let normalized: String
            let name: String
            var path: String?
            let isExisting: Bool
        }

        let entries: [RepoEntry] = urls.map { url in
            let name = URLHelpers.repoName(from: url)
            let normalized = URLHelpers.normalize(url)
            let path = urlToPath[normalized]
            return RepoEntry(url: url, normalized: normalized, name: name, path: path, isExisting: path != nil)
        }

        // ── Resolve dep levels (manifest + hook.sh, merged) ─────────

        let levels: [[String]]
        let depsByURL: [String: [String]]
        do {
            let resolved = try DependencyResolver.resolveLevels(urls, manifestDeps: manifestDeps)
            levels = resolved.levels
            depsByURL = resolved.deps
        } catch {
            print()
            print("  " + styled("Dependency error: \(error)", .red))
            return
        }

        let urlToEntryIdx: [String: Int] = Dictionary(
            uniqueKeysWithValues: entries.enumerated().map { (URLHelpers.normalize($1.url), $0) }
        )

        // Visibility: announce the resolved level structure when deps are
        // in play (>1 level).
        if levels.count > 1 {
            let summary = levels.enumerated()
                .map { "L\($0.offset + 1):\($0.element.count)" }
                .joined(separator: " ")
            print("  \(styled("\(levels.count) dependency levels", .bold))  \(styled(summary, .dim))")
        }

        // ── Phase 2: clone/pull + hooks (level by level) ────────────

        print()

        let spinner = ProgressSpinner()
        let entryCount = entries.count
        let lock = NSLock()
        nonisolated(unsafe) var completed = 0
        nonisolated(unsafe) var okCount = 0
        nonisolated(unsafe) var failedCount = 0
        nonisolated(unsafe) var cascadedSet = Set<String>()  // hooks that ran successfully — fire downstream cascades
        var rowBuffer = Array(
            repeating: RowResult(relativePath: "", url: "", normalized: "", level: 0, outcome: .unchanged, hookResult: nil, duration: 0, trigger: .noOp),
            count: entryCount
        )

        spinner.label = styled("Wrangling\u{2026}", .bold) + "  " + styled("\(entryCount) repos", .dim)
        spinner.status = styled("[0/\(entryCount)]", .dim)
        spinner.start()

        rowBuffer.withUnsafeMutableBufferPointer { buf in
            nonisolated(unsafe) let buffer = buf
            for (levelIdx, level) in levels.enumerated() {
                let levelIndices = level.compactMap { urlToEntryIdx[$0] }
                DispatchQueue.concurrentPerform(iterations: levelIndices.count) { localIdx in
                    let i = levelIndices[localIdx]
                    let entry = entries[i]
                    let relativePath = URLHelpers.pathAfterHost(from: entry.url)
                    let startTime = CFAbsoluteTimeGetCurrent()

                    spinner.activate("\(i)", name: relativePath)

                    // --- Sync (clone or pull) ---
                    let outcome: SyncOutcome
                    var resolvedPath = entry.path
                    if !entry.isExisting {
                        let clonePath = "\(devDir)/\(URLHelpers.pathAfterHost(from: entry.url))"
                        outcome = cloneRepo(url: entry.url, path: clonePath, cloneProtocol: cloneProtocol)
                        if case .synced = outcome { resolvedPath = clonePath }
                    } else if let existingPath = entry.path {
                        outcome = pullRepo(path: existingPath)
                        if case .failed = outcome, !forceHooks { resolvedPath = nil }
                    } else {
                        outcome = .unchanged
                    }

                    // --- Decide whether the hook fires ---
                    // 4 reasons to run a hook:
                    //   1. New clone (lifecycle: install)
                    //   2. Own source drifted (.synced)
                    //   3. Cascade: an upstream dep ran successfully
                    //   4. --force-hooks
                    let isNewClone: Bool = {
                        if !entry.isExisting, case .synced = outcome { return true }
                        return false
                    }()
                    let ownDrift: Bool = {
                        if entry.isExisting, case .synced = outcome { return true }
                        return false
                    }()
                    let cascadingFrom: [String] = {
                        let deps = depsByURL[entry.normalized] ?? []
                        lock.lock()
                        defer { lock.unlock() }
                        return deps.filter { cascadedSet.contains($0) }
                    }()
                    let isCascade = !cascadingFrom.isEmpty

                    var trigger: Trigger
                    var hookResult: HookResult? = nil
                    let canRunHook = runHooks && resolvedPath != nil && HookResolver.hasHook(for: entry.url)
                    let shouldRun = canRunHook && (isNewClone || ownDrift || isCascade || forceHooks)

                    // Map outcome → trigger preliminary state
                    if case .skipped = outcome {
                        trigger = .skippedDirty
                    } else if case .failed = outcome {
                        trigger = .syncFailed
                    } else if !shouldRun {
                        trigger = .noOp
                    } else if forceHooks && !ownDrift && !isCascade && !isNewClone {
                        trigger = .forced
                    } else if isNewClone {
                        trigger = .install
                    } else if ownDrift {
                        trigger = .ownDrift
                    } else {
                        trigger = .cascade(from: cascadingFrom)
                    }

                    if shouldRun, let repoPath = resolvedPath {
                        let lifecycle: Lifecycle = isNewClone ? .install : .update
                        if let resolution = HookResolver.resolve(for: entry.url, lifecycle: lifecycle) {
                            let r = HookResolver.execute(resolution, at: repoPath, repoURL: entry.url)
                            hookResult = r
                            switch r {
                            case .ran(_, let exit, let summary, _):
                                if exit == 0 {
                                    lock.lock()
                                    cascadedSet.insert(entry.normalized)
                                    lock.unlock()
                                } else {
                                    trigger = .hookFailed(summary: summary)
                                }
                            case .timedOut(_, let ran, let threshold, let median, _):
                                trigger = .hookTimedOut(ranSeconds: ran, threshold: threshold, median: median)
                            case .skipped:
                                // Hook explicitly returned 2 — no-op signal.
                                // Don't cascade and don't mark as failure.
                                break
                            case .pending:
                                break
                            }
                        }
                    }

                    let duration = CFAbsoluteTimeGetCurrent() - startTime

                    // --- Record (synchronized) ---
                    lock.lock()
                    completed += 1
                    results.record(outcome, name: entry.name)
                    let isFatal: Bool = {
                        if case .failed = outcome { return true }
                        if let h = hookResult, h.isFailure { return true }
                        return false
                    }()
                    if isFatal {
                        failedCount += 1
                        let reason: String
                        switch trigger {
                        case .syncFailed:
                            if case .failed(let r) = outcome { reason = r } else { reason = "sync failed" }
                        case .hookFailed(let s): reason = "hook: \(s)"
                        case .hookTimedOut(let r, let t, _): reason = "hook timed out at \(Int(r))s (threshold \(Int(t))s)"
                        default: reason = "failed"
                        }
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

                    buffer[i] = RowResult(
                        relativePath: relativePath,
                        url: entry.url,
                        normalized: entry.normalized,
                        level: levelIdx + 1,
                        outcome: outcome,
                        hookResult: hookResult,
                        duration: duration,
                        trigger: trigger
                    )
                }
            }
        }

        let rows = rowBuffer

        let syncedLabel = results.synced > 0 ? "\(results.synced) synced" : ""
        let unchangedLabel = results.unchanged > 0 ? "\(results.unchanged) unchanged" : ""
        let skippedLabel = results.skipped > 0 ? "\(results.skipped) skipped" : ""
        let failedLabel = results.failed > 0 ? "\(results.failed) failed" : ""
        let wrangleSummary = [syncedLabel, unchangedLabel, skippedLabel, failedLabel].filter { !$0.isEmpty }
        spinner.summary = "  " + styled(wrangleSummary.joined(separator: ", "), .dim)
        spinner.stop()

        renderTable(rows: rows, results: results, levelCount: levels.count)
        printSyncSummary(results)
        printFailureDetails(rows: rows)
    }

    // MARK: - Sync operations

    private static func cloneRepo(url: String, path: String, cloneProtocol: Manifest.CloneProtocol) -> SyncOutcome {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if !FS.isDirectory(parent) {
            do { try FS.createDirectory(parent) } catch {
                return .failed("cannot create directory: \(error)")
            }
        }
        let cloneURL = URLHelpers.cloneURL(from: url, protocol: cloneProtocol)
        let (output, exitCode) = Exec.run("/usr/bin/env", args: ["git", "clone", cloneURL, path], env: ["GIT_TERMINAL_PROMPT": "0"], timeout: 120)
        return exitCode == 0 ? .synced : .failed("clone failed: \(ErrorParse.summary(output))")
    }

    /// Fetch + behind-count + pull. The fetch is always done so cached
    /// `origin/<branch>` refs reflect upstream. If nothing's behind after
    /// fetch, we report `.unchanged` and skip the pull.
    private static func pullRepo(path: String) -> SyncOutcome {
        let (statusOutput, _) = Exec.git("status", "--porcelain", at: path)
        if !statusOutput.isEmpty { return .skipped }

        let (fetchOutput, fetchExit) = Exec.git("fetch", at: path, timeout: 30)
        if fetchExit != 0 { return .failed("fetch failed: \(ErrorParse.summary(fetchOutput))") }

        let (behindOutput, behindExit) = Exec.git("rev-list", "--count", "HEAD..@{u}", at: path)
        if behindExit != 0 { return .unchanged }
        let behind = Int(behindOutput) ?? 0
        if behind == 0 { return .unchanged }

        let (pullOutput, pullExit) = Exec.git("pull", "--ff-only", at: path, timeout: 60)
        return pullExit == 0 ? .synced : .failed("pull failed: \(ErrorParse.summary(pullOutput))")
    }

    // MARK: - Rendering

    private static func renderTable(rows: [RowResult], results: SyncResult, levelCount: Int) {
        let sortedRows = rows.sorted {
            if $0.level != $1.level { return $0.level < $1.level }
            return $0.relativePath.lowercased() < $1.relativePath.lowercased()
        }

        var segments: [Segment] = [
            Segment.indicators([
                Indicator("synced", color: .blue),
                Indicator("skipped (dirty)", color: .yellow),
                Indicator("sync failed", color: .red),
                Indicator("hooked", color: .green),
            ]),
        ]
        if levelCount > 1 {
            segments.append(Segment.column(TextColumn("L", sizing: .fixed(2))))
        }
        segments.append(Segment.column(TextColumn("Repo", sizing: .auto())))
        segments.append(Segment.column(TextColumn("Time", sizing: .auto())))
        segments.append(Segment.column(TextColumn("Trigger", sizing: .auto())))

        let table = TrafficLightTable(segments: segments)

        let tableRows: [TrafficLightRow] = sortedRows.map { row in
            let isSynced: Bool = { if case .synced = row.outcome { return true }; return false }()
            let isDirty: Bool = { if case .skipped = row.outcome { return true }; return false }()
            let isFailed: Bool = {
                if case .failed = row.outcome { return true }
                if let h = row.hookResult, h.isFailure { return true }
                return false
            }()
            let isHooked: Bool = {
                if let h = row.hookResult, case .ran(_, let exit, _, _) = h { return exit == 0 }
                return false
            }()

            var values: [String] = []
            if levelCount > 1 {
                values.append(styled("\(row.level)", .dim))
            }
            values.append(styledRepoPath(row.relativePath))
            // Hide duration on no-op rows — the value is meaningless and
            // the wall of "0.0s" is just visual noise.
            let didWork: Bool = {
                switch row.trigger {
                case .noOp: return false
                default: return true
                }
            }()
            values.append(didWork ? adaptiveDuration(row.duration, url: row.url) : styled("─", .dim))
            values.append(triggerLabel(row.trigger))

            return TrafficLightRow(
                indicators: [[
                    isSynced ? .on : .off,
                    isDirty ? .on : .off,
                    isFailed ? .on : .off,
                    isHooked ? .on : .off,
                ]],
                values: values
            )
        }

        let hookedCount = rows.filter {
            if let h = $0.hookResult, case .ran(_, let exit, _, _) = h { return exit == 0 }
            return false
        }.count
        let counts: [[Int]] = [[results.synced, results.skipped, results.failed, hookedCount]]
        print(table.render(rows: tableRows, counts: counts, terminalWidth: terminalWidth()), terminator: "")
    }

    private static func triggerLabel(_ trigger: Trigger) -> String {
        switch trigger {
        case .noOp:                     return styled("─", .dim)
        case .ownDrift:                 return styled("drift", .blue)
        case .install:                  return styled("install", .green)
        case .forced:                   return styled("forced", .magenta)
        case .cascade(let from):
            let names = from.prefix(2).map { URLHelpers.repoName(from: $0) }.joined(separator: ", ")
            let suffix = from.count > 2 ? " +\(from.count - 2)" : ""
            return styled("cascade ← \(names)\(suffix)", .cyan)
        case .skippedDirty:             return styled("dirty", .yellow)
        case .syncFailed:               return styled("sync failed", .red)
        case .hookFailed(let s):
            return styled("hook failed: \(truncate(s, 40))", .red)
        case .hookTimedOut(let r, let t, _):
            return styled("timed out at \(Int(r))s (>\(Int(t))s)", .red)
        }
    }

    /// Adaptive coloring: green within 1.5× median, yellow up to 3×, red beyond.
    /// Falls back to absolute thresholds when there's no timing history yet.
    private static func adaptiveDuration(_ seconds: TimeInterval, url: String) -> String {
        let text: String
        if seconds < 60 {
            text = String(format: "%.1fs", seconds)
        } else {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            text = "\(m)m\(s)s"
        }

        if let stats = Timings.stats(for: url), stats.count >= Timings.minSamplesForStats {
            let m = stats.median
            if m <= 0 || seconds < m * 1.5 { return styled(text, .dim) }
            if seconds < m * 3 { return styled(text, .yellow) }
            return styled(text, .red)
        }

        // Cold-start fallback (no history yet).
        if seconds < 2 { return styled(text, .dim) }
        if seconds < 10 { return styled(text, .yellow) }
        return styled(text, .red)
    }

    private static func truncate(_ s: String, _ max: Int) -> String {
        if s.count <= max { return s }
        let idx = s.index(s.startIndex, offsetBy: max - 1)
        return String(s[..<idx]) + "\u{2026}"
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

    /// For each failure, print: name, one-line summary, last few lines of
    /// output, and the unified-log query that gives the full picture.
    private static func printFailureDetails(rows: [RowResult]) {
        let failures = rows.filter {
            if case .failed = $0.outcome { return true }
            if let h = $0.hookResult, h.isFailure { return true }
            return false
        }
        guard !failures.isEmpty else { return }

        print()
        for row in failures {
            print("  " + styled("\u{2716}", .red) + " " + styled(row.relativePath, .bold))

            let summary: String
            let tail: String
            switch row.hookResult {
            case .ran(_, _, let s, let t):
                summary = s
                tail = t
            case .timedOut(_, let ran, let threshold, _, let t):
                summary = "timed out at \(Int(ran))s (threshold \(Int(threshold))s)"
                tail = t
            default:
                if case .failed(let msg) = row.outcome {
                    summary = msg
                    tail = ""
                } else {
                    summary = ""
                    tail = ""
                }
            }

            if !summary.isEmpty {
                print("    " + styled("└─", .dim) + " " + summary)
            }
            if !tail.isEmpty {
                let lines = tail.components(separatedBy: "\n")
                print("    " + styled("└─ tail (\(lines.count) lines):", .dim))
                for line in lines {
                    print("       " + styled(line, .dim))
                }
            }
            print("    " + styled("└─ log show --predicate 'subsystem == \"com.ansilithic.saddle\" AND category == \"hooks\"' --last 10m", .dim))
            print()
        }
    }
}
