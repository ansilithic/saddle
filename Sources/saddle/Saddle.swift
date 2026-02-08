import ArgumentParser
import CLICore

@main
struct Saddle: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Repository orchestrator for ~/Developer.",
        version: "1.0.0",
        subcommands: [Status.self, Up.self, Remote.self],
        defaultSubcommand: Status.self
    )
}
