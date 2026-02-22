import ArgumentParser
import CLICore
import Foundation

struct Up: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clone missing repos and pull latest changes."
    )

    @Flag(name: .long, help: "Skip running hooks after sync.")
    var noHooks = false

    func run() throws {
        let path = Config.manifestPath
        guard FS.exists(path) else {
            Output.error("No manifest found at \(FS.shortenPath(path))")
            throw ExitCode.failure
        }

        print()
        print("  \(styled("Reading manifest\u{2026}", .bold))  \(styled(FS.shortenPath(path), .dim))")

        guard let manifest = Parser.parseOrNil(at: path) else {
            throw ExitCode.failure
        }

        if manifest.repos.isEmpty {
            print(styled("No repos declared in manifest.", .dim))
            return
        }

        print("  \(styled("\(manifest.repos.count) repos declared, mount at \(FS.shortenPath(manifest.mount))", .dim))")

        Sync.syncDeclaredRepos(manifest.repos, mount: manifest.mount, cloneProtocol: manifest.cloneProtocol, runHooks: !noHooks)

        State.touchLastRun()
    }
}
