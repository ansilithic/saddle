import ArgumentParser
import CLICore
import Foundation

struct Unequip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a repo from the manifest."
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

        let path = Config.manifestPath
        guard FS.exists(path), var manifest = Parser.parseOrNil(at: path) else {
            Output.error("No manifest found at \(FS.shortenPath(Config.manifestPath))")
            throw ExitCode.failure
        }

        guard let index = manifest.repos.firstIndex(of: normalized) else {
            Output.error("Not equipped: \(normalized)")
            throw ExitCode.failure
        }

        manifest.repos.remove(at: index)

        try Parser.save(manifest, to: path)
        print(styled("Unequipped", .yellow) + " " + normalized)
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
