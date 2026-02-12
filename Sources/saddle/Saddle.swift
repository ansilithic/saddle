import ArgumentParser
import CLICore

@main
struct Saddle: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A personal package manager for your repos.",
        version: "1.0.0",
        subcommands: [Status.self, Up.self, Equip.self, Unequip.self, Adopt.self, Info.self],
        defaultSubcommand: Status.self
    )

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let subcommands = Set(["status", "up", "equip", "unequip", "adopt", "info"])
        let isTopLevel = !args.contains(where: { subcommands.contains($0) })
        let wantsHelp = args.contains("-h") || args.contains("--help")
            || args.first == "help" && args.count <= 1

        if isTopLevel && wantsHelp {
            Help.print()
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
