import CLICore

enum Help {
    struct Entry {
        let name: String
        let args: String
        let description: String
        let tag: String?

        var labelWidth: Int {
            args.isEmpty ? name.count : name.count + 1 + args.count
        }
    }

    struct FilterGroup {
        let title: String
        let entries: [Entry]
    }

    static let commands: [Entry] = [
        Entry(name: "status", args: "[filters]", description: "Show status of all repos", tag: "default"),
        Entry(name: "up", args: "", description: "Clone missing repos, pull updates, and run hooks", tag: nil),
        Entry(name: "equip", args: "[<repo>]", description: "Clone, install, and add a repo to the manifest", tag: nil),
        Entry(name: "unequip", args: "[<repo>]", description: "Uninstall and remove a repo from the manifest", tag: nil),
        Entry(name: "adopt", args: "", description: "Add all stray repos with an origin to the manifest", tag: nil),
        Entry(name: "info", args: "", description: "Show saddle configuration and status", tag: nil),
    ]

    static let filterGroups: [FilterGroup] = [
        FilterGroup(title: "Presence", entries: [
            Entry(name: "--all", args: "", description: "All repos, including archived", tag: nil),
            Entry(name: "--local", args: "", description: "Cloned to disk (equipped + stray)", tag: "default"),
            Entry(name: "--equipped", args: "", description: "In the manifest", tag: nil),
            Entry(name: "--unequipped", args: "", description: "Not in the manifest", tag: nil),
            Entry(name: "--stray", args: "", description: "Cloned locally but not in the manifest", tag: nil),
        ]),
        FilterGroup(title: "Visibility", entries: [
            Entry(name: "--public", args: "", description: "Public visibility on remote", tag: nil),
            Entry(name: "--private", args: "", description: "Private visibility on remote", tag: nil),
        ]),
        FilterGroup(title: "Working Tree", entries: [
            Entry(name: "--clean", args: "", description: "No uncommitted changes", tag: nil),
            Entry(name: "--dirty", args: "", description: "Has uncommitted changes", tag: nil),
        ]),
        FilterGroup(title: "Hooks", entries: [
            Entry(name: "--hooked", args: "", description: "Has a post-sync hook", tag: nil),
            Entry(name: "--unhooked", args: "", description: "No post-sync hook", tag: nil),
        ]),
        FilterGroup(title: "Lifecycle", entries: [
            Entry(name: "--archived", args: "", description: "Archived on remote", tag: nil),
            Entry(name: "--active", args: "", description: "Not archived", tag: nil),
        ]),
        FilterGroup(title: "Stars", entries: [
            Entry(name: "--starred", args: "", description: "Starred on remote", tag: nil),
            Entry(name: "--unstarred", args: "", description: "Not starred", tag: nil),
        ]),
        FilterGroup(title: "Other", entries: [
            Entry(name: "--owner", args: "<owner>", description: "Filter by repository owner", tag: nil),
        ]),
    ]

    static let options: [Entry] = [
        Entry(name: "-h, --help", args: "", description: "Show help information", tag: nil),
        Entry(name: "-v, --version", args: "", description: "Show the version", tag: nil),
    ]

    static func print() {
        let allEntries = commands + [showLegend] + filterGroups.flatMap(\.entries) + options
        let labelWidth = allEntries.map(\.labelWidth).max()! + 3

        Swift.print()
        Swift.print("  \(styled("saddle", .bold, .white))  \(styled("Portable dev environment \u{2014} one manifest, every machine.", .dim))")
        Swift.print()
        Swift.print("  \(styled("Usage", .bold))  \(styled("saddle", .white)) \(styled("<command>", .cyan)) \(styled("[options]", .dim))")
        Swift.print()
        printSection("Commands", commands, labelWidth: labelWidth)
        printFilterSections(labelWidth: labelWidth)
        printSection("Options", options, labelWidth: labelWidth)
    }

    static let showLegend = Entry(name: "--show-legend", args: "", description: "Display the status legend", tag: nil)

    private static func styledLabel(_ entry: Entry, paddedTo width: Int) -> String {
        if entry.args.isEmpty {
            return styled(entry.name, .cyan).padded(to: width)
        }
        return (styled(entry.name, .cyan) + " " + styled(entry.args, .dim)).padded(to: width)
    }

    private static func printFilterSections(labelWidth: Int) {
        Swift.print("  \(styled("Status Filters", .bold))")
        Swift.print()
        let label = styledLabel(showLegend, paddedTo: labelWidth)
        let desc = styled(showLegend.description, .white)
        Swift.print("    \(label)\(desc)")
        Swift.print()
        for group in filterGroups {
            Swift.print("    \(styled(group.title, .dim))")
            for entry in group.entries {
                let label = styledLabel(entry, paddedTo: labelWidth - 2)
                let desc = styled(entry.description, .white)
                let tag = entry.tag.map { " " + styled("(\($0))", .dim) } ?? ""
                Swift.print("      \(label)\(desc)\(tag)")
            }
        }
        Swift.print()
    }

    private static func printSection(_ title: String, _ entries: [Entry], labelWidth: Int) {
        Swift.print("  \(styled(title, .bold))")
        Swift.print()
        for entry in entries {
            let label = styledLabel(entry, paddedTo: labelWidth)
            let desc = styled(entry.description, .white)
            let tag = entry.tag.map { " " + styled("(\($0))", .dim) } ?? ""
            Swift.print("    \(label)\(desc)\(tag)")
        }
        Swift.print()
    }
}
