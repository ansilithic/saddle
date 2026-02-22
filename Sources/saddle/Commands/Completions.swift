import ArgumentParser

struct Completions: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate zsh completion script.",
        shouldDisplay: false
    )

    func run() {
        var lines: [String] = []

        lines.append("#compdef saddle")
        lines.append("")
        lines.append("_saddle() {")
        lines.append("    local context state state_descr line")
        lines.append("    local -A opt_args")
        lines.append("")
        lines.append("    _arguments -C \\")
        lines.append("        '(-h --help)'{-h,--help}'[Show help]' \\")
        lines.append("        '(-v --version)'{-v,--version}'[Show version]' \\")
        lines.append("        '1:command:->command' \\")
        lines.append("        '*::arg:->args'")
        lines.append("")
        lines.append("    case \"$state\" in")
        lines.append("    command)")

        // Commands from Help data
        lines.append("        local -a commands=(")
        for cmd in Help.commands {
            let escaped = cmd.description.replacingOccurrences(of: "'", with: "'\\''")
            lines.append("            '\(cmd.name):\(escaped)'")
        }
        lines.append("        )")
        lines.append("        _describe 'command' commands")
        lines.append("        ;;")

        lines.append("    args)")
        lines.append("        case \"$words[1]\" in")

        // Status subcommand — all filters
        lines.append("        status)")
        lines.append("            _arguments \\")
        var allFilters: [Help.Entry] = []
        for group in Help.filterGroups {
            allFilters.append(contentsOf: group.entries)
        }
        for (i, entry) in allFilters.enumerated() {
            let escaped = entry.description.replacingOccurrences(of: "'", with: "'\\''")
            let hasArg = entry.args.isEmpty ? "" : ":\(entry.args):"
            let continuation = i < allFilters.count - 1 ? " \\" : ""
            lines.append("                '\(entry.name)[\(escaped)]\(hasArg)'\(continuation)")
        }
        lines.append("            ;;")

        // Equip/unequip — repo argument
        lines.append("        equip|unequip)")
        lines.append("            _arguments ':repo:'")
        lines.append("            ;;")

        lines.append("        esac")
        lines.append("        ;;")
        lines.append("    esac")
        lines.append("}")
        lines.append("")
        lines.append("_saddle \"$@\"")

        print(lines.joined(separator: "\n"))
    }
}
