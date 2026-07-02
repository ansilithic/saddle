import Foundation

/// Structured output helpers. Info/success go to stdout; warnings/errors go to stderr.
public enum Output {
    public static func info(_ message: String) {
        print("\(styled("info:", .cyan)) \(message)")
    }

    public static func success(_ message: String) {
        print("\(styled("done:", .green)) \(message)")
    }

    public static func warning(_ message: String) {
        fputs("\(styled("warn:", .yellow)) \(message)\n", stderr)
    }

    public static func error(_ message: String) {
        fputs("\(styled("error:", .red)) \(message)\n", stderr)
    }

    /// Print a summary footer in the standard `── part1, part2 ──` format.
    public static func printSummary(_ parts: [String]) {
        guard !parts.isEmpty else { return }
        print(styled("\u{2500}\u{2500} ", .dim) + parts.joined(separator: styled(", ", .dim)) + styled(" \u{2500}\u{2500}", .dim))
    }
}
