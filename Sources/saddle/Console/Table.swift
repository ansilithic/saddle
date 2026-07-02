import Foundation

/// Formats tabular data with ANSI-aware column widths and consistent styling.
public struct TableFormatter: Sendable {

    public struct Column: Sendable {
        public let header: String
        public let minWidth: Int

        public init(_ header: String, minWidth: Int = 0) {
            self.header = header
            self.minWidth = minWidth
        }
    }

    private let columns: [Column]
    private let padding: Int

    public init(columns: [Column], padding: Int = 4) {
        self.columns = columns
        self.padding = padding
    }

    /// Calculate column widths from data rows. Each row is an array of display strings.
    public func widths(for rows: [[String]]) -> [Int] {
        columns.enumerated().map { i, col in
            let headerWidth = col.header.count
            let maxData = rows.map { row in
                i < row.count ? row[i].strippingANSI.count : 0
            }.max() ?? 0
            return max(col.minWidth, max(headerWidth, maxData)) + padding
        }
    }

    /// Print a styled header row and divider.
    public func printHeader(widths: [Int], indent: Int = 3) {
        let prefix = String(repeating: " ", count: indent)
        let header = columns.enumerated().map { i, col in
            if i < columns.count - 1 {
                return col.header.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            }
            return col.header
        }.joined()

        print(styled(prefix + header, .dim))

        let totalWidth = widths.reduce(0, +) + indent + 20
        print(styled(String(repeating: "\u{2500}", count: totalWidth), .dim))
    }

    /// Print a row of values using pre-calculated widths.
    public func printRow(_ values: [String], widths: [Int], prefix: String = "   ") {
        let line = values.enumerated().map { i, val in
            if i < values.count - 1 && i < widths.count {
                return val.padded(to: widths[i])
            }
            return val
        }.joined()

        print(prefix + line)
    }
}
