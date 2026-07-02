import Foundation

// MARK: - Public Types

/// A single indicator definition in a traffic-light group.
public struct Indicator: Sendable {
    public let label: String
    public let color: Color
    public let symbol: String

    public init(_ label: String, color: Color, symbol: String = "\u{25CF}") {
        self.label = label
        self.color = color
        self.symbol = symbol
    }
}

/// Column sizing strategy.
public enum ColumnSizing: Sendable {
    /// Width determined by content, optionally capped.
    case auto(maxWidth: Int? = nil)
    /// Fixed character width.
    case fixed(Int)
    /// Takes remaining terminal width, with a minimum.
    case flexible(minWidth: Int)
}

/// A text column with header and sizing.
public struct TextColumn: Sendable {
    public let header: String
    public let sizing: ColumnSizing

    public init(_ header: String, sizing: ColumnSizing = .auto()) {
        self.header = header
        self.sizing = sizing
    }
}

/// A segment in the table layout — either an indicator group or a text column.
public enum Segment: Sendable {
    case indicators([Indicator])
    case column(TextColumn)
}

/// Per-row state for a single indicator position.
public enum IndicatorState: Sendable {
    /// Indicator not shown (renders as space).
    case off
    /// Indicator shown in its defined color.
    case on
}

/// One row of data for a traffic-light table.
public struct TrafficLightRow: Sendable {
    /// One sub-array per indicator group segment, matching segment order.
    public let indicators: [[IndicatorState]]
    /// One string per column segment, matching segment order.
    public let values: [String]

    public init(indicators: [[IndicatorState]], values: [String]) {
        self.indicators = indicators
        self.values = values
    }
}

// MARK: - TrafficLightTable

/// Renders a table with interleaved indicator dot groups and text columns,
/// including optional wiring-diagram legends.
public struct TrafficLightTable: Sendable {
    public let segments: [Segment]
    public let columnPadding: Int

    public init(segments: [Segment], columnPadding: Int = 2) {
        self.segments = segments
        self.columnPadding = columnPadding
    }

    /// Render the complete table to a string.
    ///
    /// - Parameters:
    ///   - rows: Data rows. Each row's `indicators` and `values` match segment order.
    ///   - counts: Per-group indicator counts for the legend. Omit to skip the legend.
    ///   - terminalWidth: Override terminal width detection.
    public func render(
        rows: [TrafficLightRow],
        counts: [[Int]]? = nil,
        terminalWidth: Int? = nil
    ) -> String {
        let width = terminalWidth ?? defaultTerminalWidth()
        let resolvedWidths = resolveWidths(rows: rows, terminalWidth: width)

        var output = "\n"

        if let counts, !counts.isEmpty {
            output += renderLegend(counts: counts, widths: resolvedWidths)
        }

        output += renderHeader(widths: resolvedWidths)
        output += styled(String(repeating: "\u{2500}", count: width), .dim) + "\n"

        for row in rows {
            output += renderRow(row, widths: resolvedWidths)
        }

        return output
    }

    // MARK: - Width Resolution

    private func resolveWidths(rows: [TrafficLightRow], terminalWidth: Int) -> [Int] {
        var widths = [Int](repeating: 0, count: segments.count)
        var autoIndices: [Int] = []
        var autoIdealWidths: [Int] = []
        var flexibleIndex: Int? = nil
        var flexibleMinWidth = 0
        var fixedTotal = 0
        var columnIndex = 0

        for (i, segment) in segments.enumerated() {
            switch segment {
            case .indicators(let indicators):
                let w = indicators.count + columnPadding
                widths[i] = w
                fixedTotal += w

            case .column(let col):
                let ci = columnIndex
                switch col.sizing {
                case .fixed(let size):
                    let w = size + columnPadding
                    widths[i] = w
                    fixedTotal += w

                case .auto(let maxWidth):
                    let headerWidth = col.header.count
                    let maxData = rows.map { row in
                        ci < row.values.count ? row.values[ci].strippingANSI.count : 0
                    }.max() ?? 0
                    var ideal = max(headerWidth, maxData) + columnPadding
                    if let cap = maxWidth {
                        ideal = min(ideal, cap + columnPadding)
                    }
                    autoIndices.append(i)
                    autoIdealWidths.append(ideal)
                    widths[i] = ideal

                case .flexible(let minWidth):
                    flexibleIndex = i
                    flexibleMinWidth = minWidth
                }
                columnIndex += 1
            }
        }

        let autoTotal = autoIdealWidths.reduce(0, +)
        let available = terminalWidth - fixedTotal - flexibleMinWidth

        if autoTotal > available && autoTotal > 0 {
            for (j, idx) in autoIndices.enumerated() {
                let proportion = Double(autoIdealWidths[j]) / Double(autoTotal)
                let headerMin: Int
                if case .column(let col) = segments[idx] {
                    headerMin = col.header.count + columnPadding
                } else {
                    headerMin = columnPadding
                }
                widths[idx] = max(headerMin, Int(Double(available) * proportion))
            }
        }

        if let fi = flexibleIndex {
            let used = widths.enumerated()
                .filter { $0.offset != fi }
                .map(\.element)
                .reduce(0, +)
            widths[fi] = max(flexibleMinWidth, terminalWidth - used)
        }

        return widths
    }

    // MARK: - Legend

    private func renderLegend(counts: [[Int]], widths: [Int]) -> String {
        struct GroupInfo {
            let indicators: [Indicator]
            let counts: [Int]
            let offset: Int
        }

        var groups: [GroupInfo] = []
        var groupIndex = 0
        var offset = 0

        for (i, segment) in segments.enumerated() {
            if case .indicators(let indicators) = segment {
                let c = groupIndex < counts.count ? counts[groupIndex] : []
                groups.append(GroupInfo(indicators: indicators, counts: c, offset: offset))
                groupIndex += 1
            }
            offset += widths[i]
        }

        guard !groups.isEmpty else { return "" }

        let maxSlots = groups.map(\.indicators.count).max() ?? 0
        var output = ""

        for slot in 0..<maxSlots {
            var line = ""
            var currentPos = 0

            for group in groups {
                if currentPos < group.offset {
                    line += String(repeating: " ", count: group.offset - currentPos)
                    currentPos = group.offset
                }

                let slots = group.indicators.count
                if slot < slots {
                    var wiring = ""
                    for c in 0..<slots {
                        if c == slot {
                            wiring += "\u{250C}"
                        } else if c < slot {
                            wiring += "\u{2502}"
                        } else {
                            wiring += "\u{2500}"
                        }
                    }
                    wiring += "\u{2500}"

                    let indicator = group.indicators[slot]
                    let count = slot < group.counts.count ? group.counts[slot] : 0
                    let countStr = "(\(count))"

                    line += styled(wiring, .dim) + " "
                        + styled(indicator.symbol, indicator.color) + " "
                        + styled(indicator.label, indicator.color) + " "
                        + styled(countStr, .dim)

                    let visibleWidth = slots + 1 + 1 + indicator.symbol.count + 1
                        + indicator.label.count + 1 + countStr.count
                    currentPos += visibleWidth
                } else {
                    line += styled(String(repeating: "\u{2502}", count: slots), .dim)
                    currentPos += slots
                }
            }

            output += line + "\n"
        }

        // Footer pipes
        var footer = ""
        var currentPos = 0
        for group in groups {
            if currentPos < group.offset {
                footer += String(repeating: " ", count: group.offset - currentPos)
                currentPos = group.offset
            }
            let slots = group.indicators.count
            footer += styled(String(repeating: "\u{2502}", count: slots), .dim)
            currentPos += slots
        }
        output += footer + "\n"

        return output
    }

    // MARK: - Header

    private func renderHeader(widths: [Int]) -> String {
        var line = ""

        for (i, segment) in segments.enumerated() {
            switch segment {
            case .indicators(let indicators):
                let dots = indicators.map { styled($0.symbol, $0.color) }.joined()
                let pad = String(repeating: " ", count: widths[i] - indicators.count)
                line += dots + pad

            case .column(let col):
                let padded = col.header.padding(
                    toLength: widths[i], withPad: " ", startingAt: 0
                )
                line += styled(padded, .dim)
            }
        }

        return line + "\n"
    }

    // MARK: - Data Rows

    private func renderRow(_ row: TrafficLightRow, widths: [Int]) -> String {
        var line = ""
        var groupIndex = 0
        var columnIndex = 0

        for (i, segment) in segments.enumerated() {
            switch segment {
            case .indicators(let indicators):
                let states = groupIndex < row.indicators.count
                    ? row.indicators[groupIndex] : []

                for (j, indicator) in indicators.enumerated() {
                    let state = j < states.count ? states[j] : .off
                    switch state {
                    case .off:
                        line += " "
                    case .on:
                        line += styled(indicator.symbol, indicator.color)
                    }
                }

                line += String(repeating: " ", count: widths[i] - indicators.count)
                groupIndex += 1

            case .column:
                let value = columnIndex < row.values.count ? row.values[columnIndex] : ""
                let visible = value.strippingANSI

                if visible.count > widths[i] {
                    line += value.truncatedANSI(to: widths[i]).padded(to: widths[i])
                } else {
                    line += value.padded(to: widths[i])
                }
                columnIndex += 1
            }
        }

        return line + "\n"
    }
}
