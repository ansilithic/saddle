import ArgumentParser
import CLICore
import Foundation

struct Equip: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a repo to the manifest."
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
        var manifest: Manifest
        if FS.exists(path), let existing = Parser.parseOrNil(at: path) {
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

        try Parser.save(manifest, to: path)
        print(styled("Equipped", .green) + " " + normalized)
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
