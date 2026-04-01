#if canImport(os)
import os
#endif
import CLICore
import Foundation

enum HookResult {
    case pending
    case ran(name: String, exitCode: Int32)
    case skipped(name: String)
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

    /// Execute a resolved hook script at a given repo path.
    @discardableResult
    static func execute(_ resolution: Resolution, at repoPath: String) -> HookResult {
        let fn = resolution.lifecycle.functionName
        let command: String
        if resolution.lifecycle == .update {
            command = ". '\(resolution.scriptPath)' && if declare -f \(fn) >/dev/null 2>&1; then \(fn); else install; fi"
        } else {
            command = ". '\(resolution.scriptPath)' && \(fn)"
        }
        let (output, exitCode) = Exec.run("/bin/bash", args: ["-c", command], cwd: repoPath)

        let hook = resolution.hookName
        let phase = "\(resolution.lifecycle)"

        if exitCode == 2 {
            logInfo("[\(hook)] \(phase) skipped\n\(output)")
            return .skipped(name: resolution.hookName)
        } else if exitCode == 0 {
            logInfo("[\(hook)] \(phase) ok\n\(output)")
        } else {
            logError("[\(hook)] \(phase) exit \(exitCode)\n\(output)")
        }

        return .ran(name: resolution.hookName, exitCode: exitCode)
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
