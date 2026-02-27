import ArgumentParser
import CLICore
import Foundation

struct Equip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a repo to the manifest."
    )

    @Argument(help: "Repo name, or full URL (host/owner/repo). Omit to detect from current directory.")
    var repo: String?

    func run() throws {
        let normalized = try GitHelpers.resolveRepoArgument(repo)

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

        manifest.repos.append(normalized)
        try Parser.save(manifest, to: manifestPath)
        print(styled("Equipped", .green) + " " + normalized)
    }

}
