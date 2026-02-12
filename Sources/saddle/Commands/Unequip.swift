import ArgumentParser
import CLICore
import Foundation

struct Unequip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uninstall and remove a repo from the manifest."
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
        guard FS.exists(manifestPath), var manifest = Parser.parseOrNil(at: manifestPath) else {
            Output.error("No manifest found at \(FS.shortenPath(Config.manifestPath))")
            throw ExitCode.failure
        }

        guard let index = manifest.repos.firstIndex(of: normalized) else {
            Output.error("Not equipped: \(normalized)")
            throw ExitCode.failure
        }

        // Find repo on disk
        let repoPath = findRepoOnDisk(url: normalized, in: manifest.mount)

        // Run uninstall hook
        if let repoPath, let resolution = HookResolver.resolve(for: normalized, lifecycle: .uninstall) {
            let spinner = BrailleSpinner(label: "Running uninstall hook\u{2026}")
            spinner.start()
            let result = HookResolver.execute(resolution, at: repoPath)
            spinner.stop()

            if case .ran(_, let exitCode, let logPath) = result, exitCode != 0 {
                Output.warning("Uninstall hook failed (exit \(exitCode))")
                print(styled("  Log: \(FS.shortenPath(logPath))", .dim))
            } else {
                print(styled("Uninstalled", .yellow) + " " + resolution.hookName)
            }
        }

        // Remove from manifest
        manifest.repos.remove(at: index)
        try Parser.save(manifest, to: manifestPath)
        print(styled("Unequipped", .yellow) + " " + normalized)
    }

    private func findRepoOnDisk(url: String, in devDir: String) -> String? {
        let normalized = URLHelpers.normalize(url)
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
