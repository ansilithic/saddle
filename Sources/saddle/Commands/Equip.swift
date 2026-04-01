import ArgumentParser
import CLICore
import Foundation

struct Equip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a repo to the manifest."
    )

    @Argument(help: "Repo name, owner/repo, or full URL (host/owner/repo). Omit to detect from current directory.")
    var repo: String?

    func run() throws {
        let normalized = try GitHelpers.resolveRepoArgument(repo)

        let manifestPath = Paths.manifestPath
        var manifest: Manifest
        if FS.exists(manifestPath), let existing = Parser.parseOrNil(at: manifestPath) {
            manifest = existing
        } else {
            let configDir = Paths.configDir
            if !FS.isDirectory(configDir) { try FS.createDirectory(configDir) }
            manifest = Manifest(mount: FS.expandPath(Parser.defaultMount), repos: [])
        }

        let normalizedExisting = Set(manifest.repos.map { URLHelpers.normalize($0) })
        if normalizedExisting.contains(normalized) {
            Output.error("Already equipped: \(normalized)")
            throw ExitCode.failure
        }

        manifest.repos.append(normalized)
        try Parser.save(manifest, to: manifestPath)
        print(styled("Equipped", .green) + " " + normalized)
    }

}
