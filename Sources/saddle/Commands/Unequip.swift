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
        guard FS.exists(manifestPath), var manifest = Parser.parseOrNil(at: manifestPath) else {
            Output.error("No manifest found at \(FS.shortenPath(Config.manifestPath))")
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
