import ArgumentParser
import CLICore
import Foundation

struct ManifestShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "manifest",
        abstract: "Show manifest contents and location."
    )

    func run() throws {
        let path = Config.manifestPath
        guard FS.exists(path), let manifest = Parser.parseOrNil(at: path) else {
            Output.error("No manifest found at \(FS.shortenPath(path))")
            throw ExitCode.failure
        }

        print(styled("Manifest", .bold, .white) + "  " + styled(FS.shortenPath(path), .dim))
        print(styled("Mount", .bold, .white) + "     " + styled(FS.shortenPath(manifest.mount), .cyan))
        print()

        let sorted = manifest.repos.sorted()
        let width = String(sorted.count).count

        for (i, repo) in sorted.enumerated() {
            let numStr = String(i + 1)
            let num = styled(String(repeating: " ", count: width - numStr.count) + numStr, .dim)
            let hooked = HookResolver.hasHook(for: repo) ? styled(" ~", .cyan) : "  "
            let parts = repo.split(separator: "/", maxSplits: 2)
            if parts.count == 3 {
                let entry = styled(String(parts[0]), .dim) + styled("/", .dim) + styled(String(parts[1]), .yellow) + styled("/", .dim) + styled(String(parts[2]), .white)
                print("  \(num)\(hooked) \(entry)")
            } else {
                print("  \(num)\(hooked) \(styled(repo, .white))")
            }
        }

        print()
        print(styled("\(sorted.count) repos", .dim))
    }
}
