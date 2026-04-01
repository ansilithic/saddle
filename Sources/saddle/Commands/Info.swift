import ArgumentParser
import CLICore
import Foundation

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show saddle configuration and status."
    )

    func run() async {
        let spinner = ProgressSpinner()
        spinner.label = styled("Loading config\u{2026}", .dim)
        spinner.start()

        let (manifest, devDir, declaredURLs) = Parser.loadManifest()
        let hostResult = await Host.fetchAllRepos(declaredURLs: declaredURLs)

        spinner.stop()

        Config.printBanner(
            manifestPath: manifest != nil ? Paths.manifestPath : nil,
            mountDir: devDir,
            authenticatedUser: hostResult.authenticatedUser
        )
    }
}
