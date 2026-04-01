import ArgumentParser
import CLICore
import Foundation

@main
struct Saddle: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Repo wrangler.",
        version: "3.0.0",
        subcommands: [Status.self, Health.self, Up.self, Equip.self, Unequip.self, ManifestShow.self, Info.self, Auth.self, Completions.self],
        defaultSubcommand: Status.self
    )

    static func main() async {
        Paths.migrateIfNeeded()

        let cacheDir = URL(fileURLWithPath: Paths.urlCacheDir)
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 10_000_000, directory: cacheDir)

        let args = Array(CommandLine.arguments.dropFirst())
        let subcommands = Set(["status", "health", "up", "equip", "unequip", "manifest", "info", "auth", "completions"])
        let isTopLevel = !args.contains(where: { subcommands.contains($0) })
        let wantsHelp = args.contains("-h") || args.contains("--help")
            || args.first == "help" && args.count <= 1
        let wantsVersion = args.contains("-v") || args.contains("--version")

        if isTopLevel && wantsHelp {
            Help.print()
            return
        }

        if wantsVersion {
            print(configuration.version)
            return
        }

        do {
            var command = try parseAsRoot()
            if var asyncCmd = command as? any AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}
