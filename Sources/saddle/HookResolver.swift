import CLICore
import Foundation
import os

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
    let isLegacy: Bool
}

enum HookResolver {

    /// Resolve a hook script for a given URL and lifecycle phase.
    ///
    /// Resolution order:
    /// 1. Consolidated format: `hooks/owner-repo/hook.sh` (functions)
    /// 2. Legacy directory format: `hooks/owner-repo/{lifecycle}.sh`
    /// 3. For `.update`: fall back to `install.sh` if no `update.sh`
    /// 4. Legacy single-file format: `hooks/owner-repo.sh` (install/update only)
    static func resolve(for url: String, lifecycle: Lifecycle, hooksDir: String = Config.hooksDir) -> Resolution? {
        let baseName = URLHelpers.hookBaseName(from: url)
        let dirPath = "\(hooksDir)/\(baseName)"

        if FS.isDirectory(dirPath) {
            // Consolidated format: hook.sh with functions
            let hookPath = "\(dirPath)/hook.sh"
            if FS.exists(hookPath) && FS.isExecutable(hookPath) {
                return Resolution(lifecycle: lifecycle, scriptPath: hookPath, hookName: baseName, isLegacy: false)
            }

            // Legacy directory format: separate lifecycle scripts
            let scriptName: String
            switch lifecycle {
            case .install:   scriptName = "install.sh"
            case .update:    scriptName = "update.sh"
            case .uninstall: scriptName = "uninstall.sh"
            case .health:    return nil
            }

            let scriptPath = "\(dirPath)/\(scriptName)"
            if FS.exists(scriptPath) && FS.isExecutable(scriptPath) {
                return Resolution(lifecycle: lifecycle, scriptPath: scriptPath, hookName: baseName, isLegacy: true)
            }

            // For update, fall back to install.sh
            if lifecycle == .update {
                let installPath = "\(dirPath)/install.sh"
                if FS.exists(installPath) && FS.isExecutable(installPath) {
                    return Resolution(lifecycle: .update, scriptPath: installPath, hookName: baseName, isLegacy: true)
                }
            }
        }

        // Legacy single-file format: owner-repo.sh (install/update only)
        if lifecycle == .install || lifecycle == .update {
            let legacyPath = "\(hooksDir)/\(baseName).sh"
            if FS.exists(legacyPath) && FS.isExecutable(legacyPath) {
                return Resolution(lifecycle: lifecycle, scriptPath: legacyPath, hookName: baseName, isLegacy: true)
            }
        }

        return nil
    }

    /// Check if any lifecycle hook exists for a URL.
    static func hasHook(for url: String, hooksDir: String = Config.hooksDir) -> Bool {
        let baseName = URLHelpers.hookBaseName(from: url)
        let dirPath = "\(hooksDir)/\(baseName)"

        if FS.isDirectory(dirPath) {
            // Consolidated format
            let hookPath = "\(dirPath)/hook.sh"
            if FS.exists(hookPath) && FS.isExecutable(hookPath) {
                return true
            }

            // Legacy directory format
            let scripts = ["install.sh", "update.sh", "uninstall.sh"]
            for script in scripts {
                let path = "\(dirPath)/\(script)"
                if FS.exists(path) && FS.isExecutable(path) {
                    return true
                }
            }
        }

        // Legacy single-file format
        let legacyPath = "\(hooksDir)/\(baseName).sh"
        return FS.exists(legacyPath) && FS.isExecutable(legacyPath)
    }

    /// Execute a resolved hook script at a given repo path.
    @discardableResult
    static func execute(_ resolution: Resolution, at repoPath: String) -> HookResult {
        let output: String
        let exitCode: Int32

        if resolution.isLegacy {
            (output, exitCode) = Exec.run(resolution.scriptPath, args: [], cwd: repoPath)
        } else {
            let fn = resolution.lifecycle.functionName
            let command: String
            if resolution.lifecycle == .update {
                // Try update(), fall back to install()
                command = ". '\(resolution.scriptPath)' && if declare -f \(fn) >/dev/null 2>&1; then \(fn); else install; fi"
            } else {
                command = ". '\(resolution.scriptPath)' && \(fn)"
            }
            (output, exitCode) = Exec.run("/bin/bash", args: ["-c", command], cwd: repoPath)
        }

        let logger = Logger(subsystem: "com.ansilithic.saddle", category: "hooks")
        let hook = resolution.hookName
        let phase = "\(resolution.lifecycle)"

        if exitCode == 2 {
            logger.info("[\(hook, privacy: .public)] \(phase, privacy: .public) skipped\n\(output, privacy: .public)")
            return .skipped(name: resolution.hookName)
        } else if exitCode == 0 {
            logger.info("[\(hook, privacy: .public)] \(phase, privacy: .public) ok\n\(output, privacy: .public)")
        } else {
            logger.error("[\(hook, privacy: .public)] \(phase, privacy: .public) exit \(exitCode)\n\(output, privacy: .public)")
        }

        return .ran(name: resolution.hookName, exitCode: exitCode)
    }
}
