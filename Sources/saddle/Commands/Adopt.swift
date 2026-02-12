import ArgumentParser
import CLICore
import Foundation

struct Adopt: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add all stray repos to the manifest."
    )

    func run() throws {
        let path = Config.manifestPath
        var manifest: Manifest
        if FS.exists(path), let existing = Parser.parseOrNil(at: path) {
            manifest = existing
        } else {
            let configDir = Config.configDir
            if !FS.isDirectory(configDir) { _ = FS.createDirectory(configDir) }
            manifest = Manifest(mount: FS.expandPath(Parser.defaultMount), repos: [])
        }

        let devDir = manifest.mount
        let declared = Set(manifest.repos.map { URLHelpers.normalize($0) })
        let discoveredPaths = FS.findRepos(in: devDir)

        var adopted: [String] = []
        for repoPath in discoveredPaths {
            let (output, rc) = Exec.git("remote", "get-url", "origin", at: repoPath)
            guard rc == 0, !output.isEmpty else { continue }
            let normalized = URLHelpers.normalize(output)
            guard !declared.contains(normalized) else { continue }
            guard !adopted.contains(normalized) else { continue }
            adopted.append(normalized)
        }

        if adopted.isEmpty {
            print(styled("No stray repos found.", .dim))
            return
        }

        manifest.repos.append(contentsOf: adopted)
        try Parser.save(manifest, to: path)

        for repo in adopted {
            print(styled("Adopted", .green) + " " + repo)
        }
        print()
        print(styled("\(adopted.count) repo\(adopted.count == 1 ? "" : "s") adopted", .green))
    }
}
