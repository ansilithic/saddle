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
        guard let contents = FS.readFile(path) else {
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
        _ = FS.writeFile(path, contents: lines.joined(separator: "\n"))
    }

}
