import Foundation

/// Extract the most useful one-line summary and a multi-line tail from a
/// process's combined output. Plain "last line" is often noise like
/// `make: *** [build] Error 1`; we'd rather surface the underlying cause
/// (e.g., `permission denied: ...`) when one is recognizable.
enum ErrorParse {

    /// Patterns scored highest first. We scan from the bottom up and pick
    /// the first match; if none match, we fall back to the actual last
    /// non-empty line.
    private static let signals: [String] = [
        "permission denied",
        "no such file",
        "command not found",
        "fatal:",
        "error:",
        "Error:",
        "ERROR",
        "failed:",
        "Failed:",
        "abort:",
        "panic:",
        "undefined reference",
        "cannot find",
        "could not",
    ]

    /// Best one-line summary of what went wrong.
    static func summary(_ output: String) -> String {
        let lines = nonEmptyLines(output)
        guard !lines.isEmpty else { return "" }
        for line in lines.reversed() {
            let lower = line.lowercased()
            if signals.contains(where: { lower.contains($0.lowercased()) }) {
                return trimmed(line)
            }
        }
        return trimmed(lines.last!)
    }

    /// Last N non-empty lines as a single newline-joined block. Used in the
    /// failure detail rendered at the bottom of `saddle up`.
    static func tail(_ output: String, lines: Int = 12) -> String {
        let all = nonEmptyLines(output)
        let slice = all.suffix(lines)
        return slice.joined(separator: "\n")
    }

    private static func nonEmptyLines(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }
}
