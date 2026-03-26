import ArgumentParser
import CLICore
import Foundation

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show saddle configuration and status."
    )

    func run() {
        let spinner = ProgressSpinner()
        spinner.label = styled("Loading config\u{2026}", .dim)
        spinner.start()

        let (manifest, devDir, declaredURLs) = Parser.loadManifest()
        let forgeResult = Forge.fetchAllRepos(declaredURLs: declaredURLs)

        spinner.stop()

        Config.printBanner(
            manifestPath: manifest != nil ? Config.manifestPath : nil,
            mountDir: devDir,
            authenticatedUser: forgeResult.authenticatedUser
        )
    }
}
