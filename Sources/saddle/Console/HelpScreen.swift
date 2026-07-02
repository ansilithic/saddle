/// Standardized help screen renderer for ansilithic CLIs.
///
/// Renders a consistent help layout:
///
///     toolname  Abstract description.
///
///     Usage  toolname <command> [options]
///
///     Section Title
///
///       entry-name [args]   Description text
///       ...
///
/// Supports flat sections and grouped sections (subcategories with
/// indented entries). Label width is computed globally for alignment.

public struct HelpEntry: Sendable {
    public let name: String
    public let args: String
    public let description: String
    public let tag: String?

    public init(
        _ name: String,
        args: String = "",
        description: String,
        tag: String? = nil
    ) {
        self.name = name
        self.args = args
        self.description = description
        self.tag = tag
    }

    /// Visible character width of the label (name + args).
    public var labelWidth: Int {
        args.isEmpty ? name.count : name.count + 1 + args.count
    }
}

public struct HelpGroup: Sendable {
    public let title: String
    public let entries: [HelpEntry]

    public init(_ title: String, entries: [HelpEntry]) {
        self.title = title
        self.entries = entries
    }
}

public enum HelpSection: Sendable {
    case entries(String, [HelpEntry])
    case groups(String, [HelpGroup])

    var allEntries: [HelpEntry] {
        switch self {
        case .entries(_, let entries): entries
        case .groups(_, let groups): groups.flatMap(\.entries)
        }
    }
}

public struct HelpScreen: Sendable {
    public let name: String
    public let abstract: String
    public let usage: String
    public let sections: [HelpSection]

    public init(
        name: String,
        abstract: String,
        usage: String,
        sections: [HelpSection]
    ) {
        self.name = name
        self.abstract = abstract
        self.usage = usage
        self.sections = sections
    }

    /// Render the full help screen to stdout.
    public func print() {
        let labelWidth = computeLabelWidth(sections)

        Swift.print()
        Swift.print(
            "  \(styled(name, .bold, .white))  \(styled(abstract, .dim))"
        )
        Swift.print()
        Swift.print(
            "  \(styled("Usage", .bold))  \(styled(name, .white)) \(usage)"
        )
        Swift.print()
        for section in sections {
            printSection(section, labelWidth: labelWidth)
        }
    }

    /// Render only the sections (no header/usage). Useful for embedding
    /// help sections inside dashboards or other custom layouts.
    public static func printSections(
        _ sections: [HelpSection],
        labelWidth: Int? = nil
    ) {
        let width = labelWidth ?? computeLabelWidth(sections)
        for section in sections {
            printSection(section, labelWidth: width)
        }
    }
}

// MARK: - Rendering

private func computeLabelWidth(_ sections: [HelpSection]) -> Int {
    let maxWidth = sections
        .flatMap(\.allEntries)
        .map(\.labelWidth)
        .max() ?? 0
    return maxWidth + 3
}

private func styledLabel(_ entry: HelpEntry, paddedTo width: Int) -> String {
    if entry.args.isEmpty {
        return styled(entry.name, .cyan).padded(to: width)
    }
    return (styled(entry.name, .cyan) + " " + styled(entry.args, .dim))
        .padded(to: width)
}

private func styledTag(_ tag: String?) -> String {
    guard let tag else { return "" }
    return " " + styled("(\(tag))", .dim)
}

private func printSection(_ section: HelpSection, labelWidth: Int) {
    switch section {
    case .entries(let title, let entries):
        Swift.print("  \(styled(title, .bold))")
        Swift.print()
        for entry in entries {
            let label = styledLabel(entry, paddedTo: labelWidth)
            let desc = styled(entry.description, .white)
            Swift.print("    \(label)\(desc)\(styledTag(entry.tag))")
        }
        Swift.print()

    case .groups(let title, let groups):
        Swift.print("  \(styled(title, .bold))")
        Swift.print()
        for group in groups {
            Swift.print("    \(styled(group.title, .dim))")
            for entry in group.entries {
                let label = styledLabel(entry, paddedTo: labelWidth - 2)
                let desc = styled(entry.description, .white)
                Swift.print("      \(label)\(desc)\(styledTag(entry.tag))")
            }
        }
        Swift.print()
    }
}
