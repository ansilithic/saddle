import ArgumentParser
import CLICore
import Foundation

struct Equip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clone, install, and add a repo to the manifest."
    )

    @Argument(help: "Normalized URL (host/owner/repo). Omit to detect from current directory.")
    var repo: String?

    func run() throws {
        let normalized: String
        if let arg = repo {
            normalized = URLHelpers.normalize(arg)
        } else {
            normalized = try detectFromCurrentDirectory()
        }

        let manifestPath = Config.manifestPath
        var manifest: Manifest
        if FS.exists(manifestPath), let existing = Parser.parseOrNil(at: manifestPath) {
            manifest = existing
        } else {
            let configDir = Config.configDir
            if !FS.isDirectory(configDir) { _ = FS.createDirectory(configDir) }
            manifest = Manifest(mount: FS.expandPath(Parser.defaultMount), repos: [])
        }

        if manifest.repos.contains(normalized) {
            Output.error("Already equipped: \(normalized)")
            throw ExitCode.failure
        }

        let devDir = manifest.mount
        let repoName = URLHelpers.repoName(from: normalized)

        // Find or clone
        let repoPath: String
        let existingPath = findExistingRepo(url: normalized, in: devDir)

        if let existing = existingPath {
            repoPath = existing
            print(styled("Found", .dim) + " " + FS.shortenPath(existing))
        } else {
            var clonePath = "\(devDir)/\(repoName)"
            var suffix = 2
            while FS.isDirectory(clonePath) {
                clonePath = "\(devDir)/\(repoName) \(suffix)"
                suffix += 1
            }

            let parent = (clonePath as NSString).deletingLastPathComponent
            if !FS.isDirectory(parent) { _ = FS.createDirectory(parent) }
            let cloneURL = URLHelpers.sshURL(from: normalized)

            let spinner = BrailleSpinner(label: "Cloning \(repoName)\u{2026}")
            spinner.start()
            let (_, exitCode) = Exec.run("/usr/bin/git", args: ["clone", cloneURL, clonePath], env: ["GIT_TERMINAL_PROMPT": "0"])
            spinner.stop()

            guard exitCode == 0 else {
                Output.error("Clone failed for \(normalized)")
                throw ExitCode.failure
            }
            print(styled("Cloned", .green) + " " + FS.shortenPath(clonePath))
            repoPath = clonePath
        }

        // Run install hook
        if let resolution = HookResolver.resolve(for: normalized, lifecycle: .install) {
            let spinner = BrailleSpinner(label: "Running install hook\u{2026}")
            spinner.start()
            let result = HookResolver.execute(resolution, at: repoPath)
            spinner.stop()

            if case .ran(_, let exitCode, let logPath) = result, exitCode != 0 {
                Output.error("Install hook failed (exit \(exitCode))")
                print(styled("  Log: \(FS.shortenPath(logPath))", .dim))
                throw ExitCode.failure
            }
            print(styled("Installed", .green) + " " + resolution.hookName)
        }

        // Add to manifest
        manifest.repos.append(normalized)
        try Parser.save(manifest, to: manifestPath)
        print(styled("Equipped", .green) + " " + normalized)
    }

    private func findExistingRepo(url: String, in devDir: String) -> String? {
        let normalized = URLHelpers.normalize(url)
        let repoName = URLHelpers.repoName(from: url)

        // Check expected path first
        let expectedPath = "\(devDir)/\(repoName)"
        if FS.isDirectory(expectedPath) {
            let (output, rc) = Exec.git("remote", "get-url", "origin", at: expectedPath)
            if rc == 0, URLHelpers.normalize(output) == normalized {
                return expectedPath
            }
        }

        // Scan mount dir for matching remote
        let discoveredPaths = FS.findRepos(in: devDir)
        for repoPath in discoveredPaths {
            let (output, rc) = Exec.git("remote", "get-url", "origin", at: repoPath)
            if rc == 0, URLHelpers.normalize(output) == normalized {
                return repoPath
            }
        }

        return nil
    }

    private func detectFromCurrentDirectory() throws -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let (output, exitCode) = Exec.git("remote", "get-url", "origin", at: cwd)
        guard exitCode == 0, !output.isEmpty else {
            Output.error("No git remote found in current directory")
            throw ExitCode.failure
        }
        return URLHelpers.normalize(output)
    }
}
