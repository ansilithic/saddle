import ArgumentParser
import CLICore
import Foundation

struct Up: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clone missing repos and pull latest changes."
    )

    func run() throws {
        let path = Config.manifestPath
        guard FS.exists(path) else {
            Output.error("No manifest found at \(FS.shortenPath(path))")
            throw ExitCode.failure
        }

        guard let manifest = Parser.parseOrNil(at: path) else {
            throw ExitCode.failure
        }

        if manifest.repos.isEmpty {
            print(styled("No repos declared in manifest.", .dim))
            return
        }

        Config.printBanner(manifestPath: path, mountDir: manifest.mount)

        Sync.syncDeclaredRepos(manifest.repos, mount: manifest.mount)

        State.touchLastRun()
    }
}
