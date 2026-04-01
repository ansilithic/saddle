import CLICore
import Foundation

struct Parser {

    enum ParseError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case emptyFile
        case invalidFormat(String)

        var description: String {
            switch self {
            case .fileNotFound(let path): return "Manifest not found: \(path)"
            case .emptyFile: return "Manifest is empty"
            case .invalidFormat(let msg): return "Invalid manifest: \(msg)"
            }
        }
    }

    static let defaultMount = "~/Developer"

    static func parse(at path: String) throws -> Manifest {
        let contents: String
        do {
            contents = try FS.readFile(path)
        } catch {
            throw ParseError.fileNotFound(path)
        }
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.emptyFile
        }

        var mount = defaultMount
        var cloneProtocol = Manifest.CloneProtocol.ssh
        var repos: [String] = []
        var inRepos = false

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed == "[repos]" {
                inRepos = true
                continue
            }

            if trimmed.hasPrefix("[") {
                inRepos = false
                continue
            }

            if inRepos {
                let value = trimmed
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty {
                    repos.append(value)
                }
                continue
            }

            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = trimmed[trimmed.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
                let raw = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
                let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

                if key == "mount" {
                    mount = value
                } else if key == "protocol" {
                    if let parsed = Manifest.CloneProtocol(rawValue: value.lowercased()) {
                        cloneProtocol = parsed
                    }
                }
            }
        }

        return Manifest(mount: FS.expandPath(mount), repos: repos, cloneProtocol: cloneProtocol)
    }

    static func parseOrNil(at path: String) -> Manifest? {
        do {
            return try parse(at: path)
        } catch {
            print(styled("Parse error: \(error)", .red))
            return nil
        }
    }

    /// Load the manifest if it exists, returning the manifest, mount dir, and declared URLs.
    static func loadManifest() -> (manifest: Manifest?, mount: String, declaredURLs: [String]) {
        let path = Paths.manifestPath
        let manifest: Manifest? = FS.exists(path) ? parseOrNil(at: path) : nil
        let mount = manifest?.mount ?? FS.expandPath(defaultMount)
        let urls = manifest?.repos ?? []
        return (manifest, mount, urls)
    }

    static func save(_ manifest: Manifest, to path: String) throws {
        var lines: [String] = []
        lines.append("mount = \"\(FS.shortenPath(manifest.mount))\"")
        if manifest.cloneProtocol != .ssh {
            lines.append("protocol = \"\(manifest.cloneProtocol.rawValue)\"")
        }
        lines.append("")
        lines.append("[repos]")
        for repo in manifest.repos.sorted() {
            lines.append("\"\(repo)\"")
        }
        lines.append("")
        try FS.writeFile(path, contents: lines.joined(separator: "\n"))
    }

}
