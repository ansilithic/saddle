import ArgumentParser
import CLICore
import Foundation

struct Unequip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a repo from the manifest."
    )

    @Argument(help: "Repo name, or full URL (host/owner/repo). Omit to detect from current directory.")
    var repo: String?

    func run() throws {
        let normalized = try GitHelpers.resolveRepoArgument(repo)

        let manifestPath = Paths.manifestPath
        guard FS.exists(manifestPath), var manifest = Parser.parseOrNil(at: manifestPath) else {
            Output.error("No manifest found at \(FS.shortenPath(Paths.manifestPath))")
            throw ExitCode.failure
        }

        guard let index = manifest.repos.firstIndex(of: normalized) else {
            Output.error("Not equipped: \(normalized)")
            throw ExitCode.failure
        }

        manifest.repos.remove(at: index)
        try Parser.save(manifest, to: manifestPath)
        print(styled("Unequipped", .yellow) + " " + normalized)
    }

}
