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
            guard let detected = GitHelpers.detectRemoteFromCurrentDirectory() else {
                Output.error("No git remote found in current directory")
                throw ExitCode.failure
            }
            normalized = detected
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
        let repoPath = GitHelpers.findRepoOnDisk(url: normalized, in: manifest.mount)

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

}
