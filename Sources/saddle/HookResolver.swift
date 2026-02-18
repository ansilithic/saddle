import CLICore
import Foundation

enum HookResult {
    case pending
    case ran(name: String, exitCode: Int32, logPath: String)
}

enum Lifecycle {
    case install
    case update
    case uninstall
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
    /// 1. Directory format: `hooks/owner-repo/{lifecycle}.sh`
    /// 2. For `.update`: fall back to `install.sh` if no `update.sh`
    /// 3. Legacy format: `hooks/owner-repo.sh` (install/update only)
    static func resolve(for url: String, lifecycle: Lifecycle, hooksDir: String = Config.hooksDir) -> Resolution? {
        let baseName = URLHelpers.hookBaseName(from: url)
        let dirPath = "\(hooksDir)/\(baseName)"

        if FS.isDirectory(dirPath) {
            let scriptName: String
            switch lifecycle {
            case .install:   scriptName = "install.sh"
            case .update:    scriptName = "update.sh"
            case .uninstall: scriptName = "uninstall.sh"
            }

            let scriptPath = "\(dirPath)/\(scriptName)"
            if FS.exists(scriptPath) && FS.isExecutable(scriptPath) {
                return Resolution(lifecycle: lifecycle, scriptPath: scriptPath, hookName: baseName, isLegacy: false)
            }

            // For update, fall back to install.sh
            if lifecycle == .update {
                let installPath = "\(dirPath)/install.sh"
                if FS.exists(installPath) && FS.isExecutable(installPath) {
                    return Resolution(lifecycle: .update, scriptPath: installPath, hookName: baseName, isLegacy: false)
                }
            }
        }

        // Legacy format: owner-repo.sh (only for install/update)
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
            let scripts = ["install.sh", "update.sh", "uninstall.sh"]
            for script in scripts {
                let path = "\(dirPath)/\(script)"
                if FS.exists(path) && FS.isExecutable(path) {
                    return true
                }
            }
        }

        // Check legacy format
        let legacyPath = "\(hooksDir)/\(baseName).sh"
        return FS.exists(legacyPath) && FS.isExecutable(legacyPath)
    }

    /// Execute a resolved hook script at a given repo path.
    @discardableResult
    static func execute(_ resolution: Resolution, at repoPath: String) -> HookResult {
        let (output, exitCode) = Exec.run(resolution.scriptPath, args: [], cwd: repoPath)

        let logsDir = Config.hookLogsDir
        if !FS.isDirectory(logsDir) { _ = FS.createDirectory(logsDir) }
        let logPath = "\(logsDir)/\(resolution.hookName).log"
        let timestamp = DateFormatting.iso8601.string(from: Date())
        let logContent = "[\(timestamp)] \(resolution.lifecycle) exit \(exitCode)\n\(output)\n"
        _ = FS.writeFile(logPath, contents: logContent)

        if exitCode != 0 {
            Log.error("Hook \(resolution.hookName) (\(resolution.lifecycle)) failed (exit \(exitCode))")
        }

        return .ran(name: resolution.hookName, exitCode: exitCode, logPath: logPath)
    }
}
