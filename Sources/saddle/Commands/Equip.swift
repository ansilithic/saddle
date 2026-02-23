import ArgumentParser
import CLICore
import Foundation

struct Equip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clone, install, and add a repo to the manifest."
    )

    @Argument(help: "Normalized URL (host/owner/repo). Omit to detect from current directory.")
    var repo: String?

    @Flag(name: .long, help: "Skip running the install hook.")
    var noHooks = false

    func run() throws {
        let normalized: String
        if let arg = repo {
            normalized = URLHelpers.normalize(arg)
        } else {
            guard let detected = GitHelpers.detectRemoteFromCurrentDirectory() else {
                Output.error("No git remote found in current directory")
                throw ExitCode.failure
            }
            normalized = detected
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
        let cloneSubpath = URLHelpers.pathAfterHost(from: normalized)

        // Find or clone
        let repoPath: String
        let existingPath = GitHelpers.findRepoOnDisk(url: normalized, in: devDir)

        if let existing = existingPath {
            repoPath = existing
            print(styled("Found", .dim) + " " + FS.shortenPath(existing))
        } else {
            var clonePath = "\(devDir)/\(cloneSubpath)"
            var suffix = 2
            while FS.isDirectory(clonePath) {
                clonePath = "\(devDir)/\(cloneSubpath)-\(suffix)"
                suffix += 1
            }

            let parent = (clonePath as NSString).deletingLastPathComponent
            if !FS.isDirectory(parent) { _ = FS.createDirectory(parent) }
            let cloneURL = URLHelpers.cloneURL(from: normalized, protocol: manifest.cloneProtocol)

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
        if !noHooks, let resolution = HookResolver.resolve(for: normalized, lifecycle: .install) {
            let spinner = BrailleSpinner(label: "Running install hook\u{2026}")
            spinner.start()
            let result = HookResolver.execute(resolution, at: repoPath)
            spinner.stop()

            if case .ran(_, let exitCode) = result, exitCode != 0 {
                Output.error("Install hook failed (exit \(exitCode))")
                print(styled("  /usr/bin/log show --predicate 'subsystem == \"com.ansilithic.saddle\"' --last 5m", .dim))
                throw ExitCode.failure
            }
            print(styled("Installed", .green) + " " + resolution.hookName)
        }

        // Add to manifest
        manifest.repos.append(normalized)
        try Parser.save(manifest, to: manifestPath)
        print(styled("Equipped", .green) + " " + normalized)
    }

}
