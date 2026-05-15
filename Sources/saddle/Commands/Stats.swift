import ArgumentParser
import CLICore
import Foundation

struct Stats: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Per-repo hook duration history and adaptive timeout thresholds."
    )

    enum SortKey: String, ExpressibleByArgument {
        case median
        case last
        case p90
        case count
        case name
    }

    @Option(name: .long, help: "Sort by: median (default), p90, last, count, name.")
    var sort: SortKey = .median

    @Flag(name: .long, help: "Reverse the sort.")
    var asc = false

    func run() throws {
        let path = Paths.manifestPath
        guard FS.exists(path) else {
            Output.error("No manifest found at \(FS.shortenPath(path))")
            throw ExitCode.failure
        }
        guard let manifest = Parser.parseOrNil(at: path) else {
            throw ExitCode.failure
        }
        if manifest.repos.isEmpty {
            print(styled("No repos declared in manifest.", .dim))
            return
        }

        struct Row {
            let url: String
            let path: String
            let stats: Timings.Stats?
            let timeout: TimeInterval?
        }

        var rows: [Row] = manifest.repos.map { url in
            let s = Timings.stats(for: url)
            return Row(
                url: url,
                path: URLHelpers.pathAfterHost(from: url),
                stats: s,
                timeout: Timings.adaptiveTimeout(for: url)
            )
        }

        rows.sort { (a, b) in
            let order: Bool
            switch sort {
            case .median:
                order = (a.stats?.median ?? -1) > (b.stats?.median ?? -1)
            case .last:
                order = (a.stats?.last ?? -1) > (b.stats?.last ?? -1)
            case .p90:
                order = (a.stats?.p90 ?? -1) > (b.stats?.p90 ?? -1)
            case .count:
                order = (a.stats?.count ?? -1) > (b.stats?.count ?? -1)
            case .name:
                order = a.path.lowercased() < b.path.lowercased()
            }
            return asc ? !order : order
        }

        let table = TrafficLightTable(segments: [
            Segment.column(TextColumn("Repo", sizing: .auto())),
            Segment.column(TextColumn("Samples", sizing: .auto())),
            Segment.column(TextColumn("Median", sizing: .auto())),
            Segment.column(TextColumn("P90", sizing: .auto())),
            Segment.column(TextColumn("Last", sizing: .auto())),
            Segment.column(TextColumn("Timeout", sizing: .auto())),
        ])

        let tableRows: [TrafficLightRow] = rows.map { r in
            let s = r.stats
            let count = s.map { String($0.count) } ?? "─"
            let median = s.map { fmtSeconds($0.median) } ?? "─"
            let p90 = s.map { fmtSeconds($0.p90) } ?? "─"
            let last = s?.last.map { fmtSeconds($0) } ?? "─"
            let timeout = r.timeout.map { fmtSeconds($0) } ?? styled("learning", .dim)

            return TrafficLightRow(
                indicators: [],
                values: [
                    styledRepoPath(r.path),
                    styled(count, s == nil ? .dim : .reset),
                    styled(median, s == nil ? .dim : .reset),
                    styled(p90, s == nil ? .dim : .reset),
                    styled(last, s == nil ? .dim : .reset),
                    timeout,
                ]
            )
        }

        print()
        print(table.render(rows: tableRows, terminalWidth: terminalWidth()), terminator: "")

        // Aggregate summary
        let withData = rows.filter { $0.stats != nil }
        let totalSamples = withData.reduce(0) { $0 + ($1.stats?.count ?? 0) }
        print()
        Output.printSummary([
            styled("\(withData.count) tracked", .green),
            styled("\(rows.count - withData.count) learning", .dim),
            styled("\(totalSamples) samples", .dim),
        ])
    }

    private func fmtSeconds(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m\(s)s"
    }
}
