import Foundation

struct Parser {

    enum ParseError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case emptyFile

        var description: String {
            switch self {
            case .fileNotFound(let path): return "Manifest not found: \(path)"
            case .emptyFile: return "Manifest is empty"
            }
        }
    }

    static let defaultRoot = "~/Developer"

    static func parse(at path: String) throws -> Manifest {
        guard let content = FS.readFile(path) else {
            throw ParseError.fileNotFound(path)
        }

        var root: String? = nil
        var urls: [String] = []

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("~/") || trimmed.hasPrefix("/") {
                root = FS.expandPath(trimmed)
            } else {
                urls.append(trimmed)
            }
        }

        guard root != nil || !urls.isEmpty else { throw ParseError.emptyFile }

        return Manifest(
            root: root ?? FS.expandPath(defaultRoot),
            urls: urls
        )
    }
}
