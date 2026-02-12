import CLICore

enum Help {
    struct Entry {
        let name: String
        let args: String
        let description: String
        let tag: String?
    }

    static let commands: [Entry] = [
        Entry(name: "status", args: "[filters]", description: "Show status of all repos", tag: "default"),
        Entry(name: "up", args: "[--dry-run]", description: "Clone missing repos and pull latest", tag: nil),
        Entry(name: "equip", args: "[<repo>]", description: "Add a repo to the manifest", tag: nil),
        Entry(name: "unequip", args: "[<repo>]", description: "Remove a repo from the manifest", tag: nil),
        Entry(name: "adopt", args: "", description: "Add all stray repos with an origin to the manifest", tag: nil),
        Entry(name: "info", args: "", description: "Show saddle configuration and status", tag: nil),
    ]

    static let filters: [Entry] = [
        Entry(name: "--all", args: "", description: "Show all repos, including archived", tag: nil),
        Entry(name: "--public", args: "", description: "Public repos only", tag: nil),
        Entry(name: "--private", args: "", description: "Private repos only", tag: nil),
        Entry(name: "--clean", args: "", description: "Clean repos only", tag: nil),
        Entry(name: "--dirty", args: "", description: "Dirty repos only", tag: nil),
        Entry(name: "--equipped", args: "", description: "Equipped repos only", tag: nil),
        Entry(name: "--unequipped", args: "", description: "Unequipped repos only", tag: nil),
        Entry(name: "--hooked", args: "", description: "Hooked repos only", tag: nil),
        Entry(name: "--unhooked", args: "", description: "Unhooked repos only", tag: nil),
        Entry(name: "--starred", args: "", description: "Starred repos only", tag: nil),
        Entry(name: "--unstarred", args: "", description: "Unstarred repos only", tag: nil),
        Entry(name: "--archived", args: "", description: "Archived repos only", tag: nil),
        Entry(name: "--active", args: "", description: "Active (non-archived) repos only", tag: "default"),
        Entry(name: "--owner", args: "<owner>", description: "Filter by repo owner", tag: nil),
        Entry(name: "--show-legend", args: "", description: "Show the status legend", tag: nil),
    ]

    static let options: [Entry] = [
        Entry(name: "-h, --help", args: "", description: "Show help information", tag: nil),
        Entry(name: "--version", args: "", description: "Show the version", tag: nil),
    ]

    static func print() {
        let allEntries = commands + filters + options
        let nameWidth = allEntries.map(\.name.count).max()! + 3
        let argsWidth = (commands + filters).map(\.args.count).max()! + 3

        Swift.print()
        Swift.print("  \(styled("saddle", .bold, .white))  \(styled("Portable dev environment \u{2014} one manifest, every machine.", .dim))")
        Swift.print()
        Swift.print("  \(styled("Usage", .bold))  \(styled("saddle", .white)) \(styled("<command>", .cyan)) \(styled("[options]", .dim))")
        Swift.print()
        printSection("Commands", commands, nameWidth: nameWidth, argsWidth: argsWidth)
        printSection("Status Filters", filters, nameWidth: nameWidth, argsWidth: argsWidth)
        printSection("Options", options, nameWidth: nameWidth, argsWidth: 0)
    }

    private static func printSection(_ title: String, _ entries: [Entry], nameWidth: Int, argsWidth: Int) {
        Swift.print("  \(styled(title, .bold))")
        Swift.print()
        for entry in entries {
            let name = styled(entry.name, .cyan).padded(to: nameWidth)
            let args = argsWidth > 0 ? styled(entry.args, .dim).padded(to: argsWidth) : ""
            let desc = styled(entry.description, .white)
            let tag = entry.tag.map { " " + styled("(\($0))", .dim) } ?? ""
            Swift.print("    \(name)\(args)\(desc)\(tag)")
        }
        Swift.print()
    }
}
