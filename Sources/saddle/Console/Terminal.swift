#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation

/// Whether stdout is connected to an interactive terminal.
/// Color output is always enabled — if a consumer needs plain text,
/// pipe through a tool that strips ANSI (e.g. `| sed 's/\x1b\[[0-9;]*m//g'`).
public let isTerminal: Bool = true

/// Detect terminal width via ioctl. Falls back to 120 columns.
public func terminalWidth() -> Int {
    var w = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0, w.ws_col > 0 {
        return Int(w.ws_col)
    }
    return 120
}

public func defaultTerminalWidth() -> Int {
    terminalWidth()
}

/// Detect terminal height via ioctl. Falls back to 40 rows.
public func terminalHeight() -> Int {
    var w = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0, w.ws_row > 0 {
        return Int(w.ws_row)
    }
    return 40
}

/// RGB color value for true-color ANSI escape sequences.
public struct RGB: Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public var fg: String { "\u{001B}[38;2;\(r);\(g);\(b)m" }

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: String) {
        let hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Foundation.Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.r = UInt8((rgb >> 16) & 0xFF)
        self.g = UInt8((rgb >> 8) & 0xFF)
        self.b = UInt8(rgb & 0xFF)
    }
}

/// One Dark color palette for terminal output.
public enum Color: Sendable {
    case reset, bold, dim
    case red, green, yellow, blue, cyan, white, gray, orange
    case magenta, lightGray, darkGray
    case darkBlue, darkRed, darkNeonGreen
    case custom(String)

    public var rawValue: String {
        switch self {
        case .reset:     return "\u{001B}[0m"
        case .bold:      return "\u{001B}[1m"
        case .dim:       return "\u{001B}[2m"
        case .red:       return RGB(hex: "E06C75").fg
        case .green:     return RGB(hex: "98C379").fg
        case .yellow:    return RGB(hex: "E5C07B").fg
        case .blue:      return RGB(hex: "61AFEF").fg
        case .cyan:      return RGB(hex: "56B6C2").fg
        case .white:     return RGB(hex: "ABB2BF").fg
        case .gray:      return RGB(hex: "6B7280").fg
        case .orange:    return RGB(hex: "D19A66").fg
        case .magenta:   return RGB(hex: "C678DD").fg
        case .lightGray: return RGB(hex: "848B98").fg
        case .darkGray:  return RGB(hex: "333842").fg
        case .darkBlue:  return RGB(hex: "4A9EC2").fg
        case .darkRed:       return RGB(hex: "C85A6A").fg
        case .darkNeonGreen: return RGB(hex: "1EA00C").fg
        case .custom(let code): return code
        }
    }
}

/// Apply ANSI color styling to text. Automatically returns plain text when not in a terminal.
public func styled(_ text: String, _ colors: Color...) -> String {
    guard isTerminal else { return text }
    let codes = colors.map { $0.rawValue }.joined()
    return "\(codes)\(text)\(Color.reset.rawValue)"
}

extension String {
    /// Repeat this string `count` times.
    public func repeating(_ count: Int) -> String {
        String(repeating: self, count: max(0, count))
    }

    /// Strip all ANSI escape sequences from a string.
    public var strippingANSI: String {
        replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }

    /// Pad to a visible width, accounting for ANSI escape sequences.
    public func padded(to width: Int) -> String {
        let visible = self.strippingANSI.count
        if visible >= width { return self }
        return self + String(repeating: " ", count: width - visible)
    }

    /// Truncate to a visible width, preserving ANSI escape sequences.
    /// Appends an ellipsis if truncation occurs and resets ANSI state.
    public func truncatedANSI(to width: Int) -> String {
        guard width > 0 else { return "" }
        let target = width - 1  // reserve space for ellipsis

        var result = ""
        var visible = 0
        var i = self.startIndex

        while i < self.endIndex && visible < target {
            if self[i] == "\u{001B}" {
                // consume the entire escape sequence
                var j = self.index(after: i)
                if j < self.endIndex && self[j] == "[" {
                    j = self.index(after: j)
                    while j < self.endIndex && self[j] != "m" {
                        j = self.index(after: j)
                    }
                    if j < self.endIndex {
                        j = self.index(after: j)  // past 'm'
                    }
                }
                result += self[i..<j]
                i = j
            } else {
                result.append(self[i])
                visible += 1
                i = self.index(after: i)
            }
        }

        result += "\u{2026}"
        if isTerminal { result += Color.reset.rawValue }
        return result
    }
}
