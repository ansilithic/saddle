import ArgumentParser
import CLICore
import Foundation

struct Up: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clone missing repos and pull latest changes."
    )

    func run() {
        let path = Config.manifestPath
        guard FS.exists(path) else {
            Output.error("No manifest found at \(Sync.shortenPath(path))")
            CLIExitCode.error.exit()
        }

        guard let manifest = parseManifest(at: path) else {
            CLIExitCode.error.exit()
        }

        if manifest.urls.isEmpty {
            print(styled("No repos declared in manifest.", .dim))
            return
        }

        print()
        print(styled("Manifest", .bold) + "        " + styled(Sync.shortenPath(path), .darkGray))
        print(styled("Hooks", .bold) + "           " + styled(Sync.shortenPath(Config.hooksDir), .darkGray))
        print(styled("Developer Root", .bold) + "  " + styled(Sync.shortenPath(manifest.root), .darkGray))

        Sync.syncDeclaredRepos(manifest.urls, root: manifest.root, dryRun: false)

        State.touchLastRun()
    }

    private func parseManifest(at path: String) -> Manifest? {
        do {
            return try Parser.parse(at: path)
        } catch {
            Output.error("Parse error: \(error)")
            return nil
        }
    }
}
