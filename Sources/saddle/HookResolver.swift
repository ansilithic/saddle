#if canImport(os)
import os
#endif
import CLICore
import Foundation

enum HookResult {
    case pending
    case ran(name: String, exitCode: Int32, summary: String, tail: String)
    case skipped(name: String)
    case timedOut(name: String, ranSeconds: Double, threshold: Double, median: Double, tail: String)

    var isSuccess: Bool {
        if case .ran(_, let exit, _, _) = self { return exit == 0 }
        return false
    }

    var isFailure: Bool {
        switch self {
        case .ran(_, let exit, _, _): return exit != 0
        case .timedOut: return true
        default: return false
        }
    }
}

enum Lifecycle {
    case install
    case update
    case uninstall
    case health

    var functionName: String {
        switch self {
        case .install:   return "install"
        case .update:    return "update"
        case .uninstall: return "uninstall"
        case .health:    return "health"
        }
    }
}

struct Resolution {
    let lifecycle: Lifecycle
    let scriptPath: String
    let hookName: String
}

enum HookResolver {

    /// Hard ceiling on hook duration when we don't yet have enough samples
    /// to compute an adaptive timeout. Generous — picked to be longer than
    /// any reasonable hook, including cold container builds.
    static let coldTimeout: TimeInterval = 600

    /// Resolve a hook script for a given URL and lifecycle phase.
    /// Only consolidated format is supported: `hooks/{owner-repo}/hook.sh` with functions.
    static func resolve(for url: String, lifecycle: Lifecycle, hooksDir: String = Paths.hooksDir) -> Resolution? {
        let baseName = URLHelpers.hookBaseName(from: url)
        let dirPath = "\(hooksDir)/\(baseName)"

        guard FS.isDirectory(dirPath) else { return nil }

        let hookPath = "\(dirPath)/hook.sh"
        guard FS.exists(hookPath) && FS.isExecutable(hookPath) else { return nil }

        return Resolution(lifecycle: lifecycle, scriptPath: hookPath, hookName: baseName)
    }

    /// Check if any lifecycle hook exists for a URL.
    static func hasHook(for url: String, hooksDir: String = Paths.hooksDir) -> Bool {
        let baseName = URLHelpers.hookBaseName(from: url)
        let hookPath = "\(hooksDir)/\(baseName)/hook.sh"
        return FS.exists(hookPath) && FS.isExecutable(hookPath)
    }

    /// Execute a resolved hook script at a given repo path. Adaptive
    /// timeout kicks in once Timings has at least `minSamplesForStats`
    /// successful runs recorded; otherwise we fall back to `coldTimeout`.
    @discardableResult
    static func execute(_ resolution: Resolution, at repoPath: String, repoURL: String) -> HookResult {
        let fn = resolution.lifecycle.functionName
        let command: String
        if resolution.lifecycle == .update {
            command = ". '\(resolution.scriptPath)' && if declare -f \(fn) >/dev/null 2>&1; then \(fn); else install; fi"
        } else {
            command = ". '\(resolution.scriptPath)' && \(fn)"
        }

        let timeout = Timings.adaptiveTimeout(for: repoURL) ?? coldTimeout
        let started = CFAbsoluteTimeGetCurrent()
        let result = Exec.runWithGrace(
            "/bin/bash",
            args: ["-c", command],
            cwd: repoPath,
            timeout: timeout
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        let hook = resolution.hookName
        let phase = "\(resolution.lifecycle)"

        if result.timedOut {
            let stats = Timings.stats(for: repoURL)
            let median = stats?.median ?? 0
            logError("[\(hook)] \(phase) timed out at \(Int(elapsed))s (threshold \(Int(timeout))s)\n\(result.output)")
            return .timedOut(
                name: hook,
                ranSeconds: elapsed,
                threshold: timeout,
                median: median,
                tail: ErrorParse.tail(result.output)
            )
        }

        if result.exitCode == 2 {
            logInfo("[\(hook)] \(phase) skipped\n\(result.output)")
            return .skipped(name: hook)
        }

        let summary = result.exitCode == 0 ? "" : ErrorParse.summary(result.output)
        let tail = result.exitCode == 0 ? "" : ErrorParse.tail(result.output)

        if result.exitCode == 0 {
            logInfo("[\(hook)] \(phase) ok\n\(result.output)")
            // Only successful runs feed the timing window — failures would
            // skew the median artificially.
            Timings.record(url: repoURL, duration: elapsed)
        } else {
            logError("[\(hook)] \(phase) exit \(result.exitCode)\n\(result.output)")
        }

        return .ran(name: hook, exitCode: result.exitCode, summary: summary, tail: tail)
    }

    private static func logInfo(_ message: String) {
        #if canImport(os)
        let logger = Logger(subsystem: "com.ansilithic.saddle", category: "hooks")
        logger.info("\(message, privacy: .public)")
        #else
        fputs("info: \(message)\n", stderr)
        #endif
    }

    private static func logError(_ message: String) {
        #if canImport(os)
        let logger = Logger(subsystem: "com.ansilithic.saddle", category: "hooks")
        logger.error("\(message, privacy: .public)")
        #else
        fputs("error: \(message)\n", stderr)
        #endif
    }
}
