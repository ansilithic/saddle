import ArgumentParser
import CLICore
import Foundation

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show saddle configuration and status."
    )

    func run() {
        let spinner = BrailleSpinner(label: "Loading config\u{2026}")
        spinner.start()

        let manifest: Manifest?
        let path = Config.manifestPath
        if FS.exists(path) {
            manifest = Parser.parseOrNil(at: path)
        } else {
            manifest = nil
        }

        let devDir = manifest?.mount ?? FS.expandPath(Parser.defaultMount)
        let forgeResult = Forge.fetchAllRepos()

        spinner.stop()

        Config.printBanner(
            manifestPath: manifest != nil ? path : nil,
            mountDir: devDir,
            authenticatedUser: forgeResult.authenticatedUser
        )
    }
}
