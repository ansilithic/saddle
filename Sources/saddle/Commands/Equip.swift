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
        let normalized: String
        if let arg = repo {
            let raw = URLHelpers.normalize(arg)
            if !raw.contains("/") {
                switch GitHelpers.resolveBareName(raw, in: FS.expandPath(Parser.defaultMount)) {
                case .resolved(let url):
                    normalized = url
                case .ambiguous(let matches):
                    Output.error("Bare name \"\(arg)\" is ambiguous:")
                    for match in matches { print("  \(match)") }
                    throw ExitCode.failure
                case .notFound:
                    Output.error("Cannot resolve bare name \"\(arg)\" — provide a full URL (e.g. github.com/owner/\(arg))")
                    throw ExitCode.failure
                }
            } else {
                normalized = raw
            }
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

        manifest.repos.append(normalized)
        try Parser.save(manifest, to: manifestPath)
        print(styled("Equipped", .green) + " " + normalized)
    }

}
