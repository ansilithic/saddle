import ArgumentParser
import CLICore
import Foundation

struct ManifestShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "manifest",
        abstract: "Show manifest contents and location."
    )

    func run() throws {
        let path = Paths.manifestPath
        guard FS.exists(path), let manifest = Parser.parseOrNil(at: path) else {
            Output.error("No manifest found at \(FS.shortenPath(path))")
            throw ExitCode.failure
        }

        print(styled("Manifest", .bold, .white) + "  " + styled(FS.shortenPath(path), .dim))
        print(styled("Mount", .bold, .white) + "     " + styled(FS.shortenPath(manifest.mount), .cyan))
        print()

        let sorted = manifest.repos.sorted()
        var hookedCount = 0

        let table = TrafficLightTable(segments: [
            .indicators([
                Indicator("hooked", color: .custom(RGB(hex: "7B2FBE").fg)),
            ]),
            .column(TextColumn("Repo", sizing: .auto())),
        ])

        var rows: [TrafficLightRow] = []

        for repo in sorted {
            let isHooked = HookResolver.hasHook(for: repo)
            if isHooked { hookedCount += 1 }

            let parts = repo.split(separator: "/", maxSplits: 2)
            let entry: String
            if parts.count == 3 {
                entry = styled(String(parts[0]), .dim) + styled("/", .dim) + styled(String(parts[1]), .yellow) + styled("/", .dim) + styled(String(parts[2]), .white)
            } else {
                entry = styled(repo, .white)
            }

            rows.append(TrafficLightRow(
                indicators: [[isHooked ? .on : .off]],
                values: [entry]
            ))
        }

        let counts: [[Int]] = [[hookedCount]]
        print(table.render(rows: rows, counts: counts, terminalWidth: terminalWidth()), terminator: "")

        print()
        print(styled("\(sorted.count) repos", .dim))
    }
}
