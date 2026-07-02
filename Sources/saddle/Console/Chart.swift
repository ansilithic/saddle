import Foundation

// MARK: - Bar

/// Horizontal bar using eighth-block characters for sub-character precision.
/// Exactly `width` visible characters. Fraction clamped to 0.0–1.0.
/// Falls back to ASCII `[####....]` when not connected to a terminal.
public func bar(
    _ fraction: Double,
    width: Int,
    fill: Color = .green,
    empty: Color = .darkGray
) -> String {
    let clamped = min(max(fraction, 0), 1)

    guard isTerminal else {
        let inner = width - 2  // account for [ ]
        let filled = Int((clamped * Double(inner)).rounded())
        let emptyCount = inner - filled
        return "[" + "#".repeating(filled) + ".".repeating(emptyCount) + "]"
    }

    let blockChars: [Character] = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
    let fullBlock: Character = "█"
    let emptyBlock = "░"

    let totalEighths = Int(clamped * Double(width) * 8)
    let fullCount = totalEighths / 8
    let partialIndex = totalEighths % 8
    let hasPartial = partialIndex > 0
    let emptyCount = width - fullCount - (hasPartial ? 1 : 0)

    var result = ""
    if fullCount > 0 {
        result += styled(String(repeating: fullBlock, count: fullCount), fill)
    }
    if hasPartial {
        result += styled(String(blockChars[partialIndex]), fill)
    }
    if emptyCount > 0 {
        result += styled(emptyBlock.repeating(emptyCount), empty)
    }
    return result
}

// MARK: - BarChart

/// Horizontal bar chart with auto-aligned labels and display values.
public struct BarChart: Sendable {

    public struct Item: Sendable {
        public let label: String
        public let value: Double
        public let display: String

        public init(_ label: String, value: Double, display: String) {
            self.label = label
            self.value = value
            self.display = display
        }
    }

    private let items: [Item]
    private let color: Color
    private let barWidth: Int?

    public init(items: [Item], color: Color = .blue, barWidth: Int? = nil) {
        self.items = items
        self.color = color
        self.barWidth = barWidth
    }

    public func render() -> String {
        guard !items.isEmpty else { return "" }

        let maxValue = items.map(\.value).max() ?? 1
        let labelWidth = items.map { $0.label.strippingANSI.count }.max() ?? 0
        let displayWidth = items.map { $0.display.strippingANSI.count }.max() ?? 0
        // 2 spaces after label, 2 spaces before display, 2 spaces after display
        let chrome = labelWidth + 2 + 2 + displayWidth
        let computedBarWidth = barWidth ?? max(10, terminalWidth() - chrome - 2)

        var lines: [String] = []
        for item in items {
            let fraction = maxValue > 0 ? item.value / maxValue : 0
            let paddedLabel = item.label.padded(to: labelWidth)
            let b = bar(fraction, width: computedBarWidth, fill: color, empty: .darkGray)
            lines.append(paddedLabel + "  " + b + "  " + item.display)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Sparkline

/// Inline sparkline using vertical block characters, one per value.
public struct Sparkline: Sendable {
    private let values: [Double]
    private let color: Color

    public init(_ values: [Double], color: Color = .cyan) {
        self.values = values
        self.color = color
    }

    public func render() -> String {
        guard !values.isEmpty else { return "" }

        let sparkChars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let range = hi - lo

        let chars = values.map { value -> Character in
            if range == 0 { return sparkChars[3] } // mid-height for equal values
            let normalized = (value - lo) / range
            let index = min(Int(normalized * 7), 7)
            return sparkChars[index]
        }

        return styled(String(chars), color)
    }
}
