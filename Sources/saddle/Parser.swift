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
        var dependencies: [String: [String]] = [:]

        enum Section { case top, repos, dependencies }
        var section: Section = .top

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed == "[repos]" { section = .repos; continue }
            if trimmed == "[dependencies]" { section = .dependencies; continue }
            if trimmed.hasPrefix("[") { section = .top; continue }

            switch section {
            case .repos:
                let value = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty { repos.append(value) }

            case .dependencies:
                if let (key, deps) = parseDependencyLine(trimmed) {
                    let normalizedKey = DependencyResolver.normalizeDep(key)
                    dependencies[normalizedKey] = deps.map { DependencyResolver.normalizeDep($0) }
                }

            case .top:
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
        }

        return Manifest(mount: FS.expandPath(mount), repos: repos, cloneProtocol: cloneProtocol, dependencies: dependencies)
    }

    /// A `[dependencies]` line: `"owner/repo" = ["dep1", "dep2"]`. Returns
    /// the raw key + dep tokens; caller normalizes via `DependencyResolver`.
    private static func parseDependencyLine(_ raw: String) -> (key: String, deps: [String])? {
        guard let eqIdx = raw.firstIndex(of: "=") else { return nil }
        let lhs = raw[raw.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let rhs = raw[raw.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
        guard !lhs.isEmpty else { return nil }

        // Strip the surrounding `[` and `]`.
        guard rhs.hasPrefix("["), rhs.hasSuffix("]") else { return nil }
        let inner = rhs.dropFirst().dropLast()

        var deps: [String] = []
        for chunk in inner.components(separatedBy: ",") {
            let token = chunk.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !token.isEmpty { deps.append(token) }
        }
        return (lhs, deps)
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
        if !manifest.dependencies.isEmpty {
            lines.append("")
            lines.append("[dependencies]")
            for key in manifest.dependencies.keys.sorted() {
                let deps = manifest.dependencies[key]!
                let formatted = deps.map { "\"\(shortName($0))\"" }.joined(separator: ", ")
                lines.append("\"\(shortName(key))\" = [\(formatted)]")
            }
        }
        lines.append("")
        try FS.writeFile(path, contents: lines.joined(separator: "\n"))
    }

    /// Strip the `github.com/` prefix when writing to keep manifests
    /// readable. The parser re-normalizes on the way back in.
    private static func shortName(_ normalized: String) -> String {
        if normalized.hasPrefix("github.com/") {
            return String(normalized.dropFirst("github.com/".count))
        }
        return normalized
    }

}
