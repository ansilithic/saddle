import ArgumentParser
import CLICore

@main
struct Saddle: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Repo wrangler for macOS.",
        version: "2.0.0",
        subcommands: [Status.self, Up.self, Equip.self, Unequip.self, Info.self, Completions.self],
        defaultSubcommand: Status.self
    )

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let subcommands = Set(["status", "up", "equip", "unequip", "info"])
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
            try command.run()
        } catch {
            exit(withError: error)
        }
    }
}
