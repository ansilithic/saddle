import CLICore
import Foundation

struct Config {
    static var configDir: String { FS.expandPath("~/.config/saddle") }
    static var hooksDir: String { "\(configDir)/hooks" }
    static var stateDir: String { FS.expandPath("~/.local/state/saddle") }

    static var manifestPath: String { "\(configDir)/manifest.toml" }
    static var stateFile: String { "\(stateDir)/state.json" }
    static var logFile: String { "\(stateDir)/saddle.log" }
    static var hookLogsDir: String { "\(stateDir)/hooks" }

    static func printBanner(manifestPath: String?, mountDir: String, authenticatedUser: String? = nil) {
        var fields: [(String, String)] = []
        if let manifestPath { fields.append(("Manifest", FS.shortenPath(manifestPath))) }
        fields.append(("Hooks", FS.shortenPath(hooksDir)))
        fields.append(("Mount", FS.shortenPath(mountDir)))
        if let authenticatedUser { fields.append(("Account", authenticatedUser)) }

        let version = Saddle.configuration.version
        let w = 38

        // Western palette
        let fr = Color.custom(RGB(hex: "8B5E3C").fg)
        let dk = Color.custom(RGB(hex: "5C3D1E").fg)
        let gd = Color.custom(RGB(hex: "DAA520").fg)
        let tn = Color.custom(RGB(hex: "C8A96E").fg)

        func pad(_ content: String) -> String {
            let padding = w - content.count
            let left = padding / 2
            let right = padding - left
            return String(repeating: " ", count: left) + content + String(repeating: " ", count: right)
        }

        let bars = String(repeating: "\u{2550}", count: w)
        let dots = String(repeating: "\u{2504}", count: w - 2)
        let sp = String(repeating: " ", count: w)

        // Helpers
        let fl = styled("\u{2551}", fr)
        func empty() -> String { fl + sp + fl }

        func centered(_ text: String) -> (left: Int, right: Int) {
            let p = w - text.count
            return (p / 2, p - p / 2)
        }

        // Divider: ━━━━━━━━━ ◆ ━━━━━━━━━ (21 visible)
        func divider() -> String {
            let c = centered("━━━━━━━━━ ◆ ━━━━━━━━━")
            return fl
                + String(repeating: " ", count: c.left)
                + styled("\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}", tn)
                + " " + styled("\u{25C6}", gd) + " "
                + styled("\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}\u{2501}", tn)
                + String(repeating: " ", count: c.right)
                + fl
        }

        // Letterpress top/bottom (25 visible)
        let lpTop = "\u{2554}\u{2550}\u{2550}\u{2550}\u{2566}\u{2550}\u{2550}\u{2550}\u{2566}\u{2550}\u{2550}\u{2550}\u{2566}\u{2550}\u{2550}\u{2550}\u{2566}\u{2550}\u{2550}\u{2550}\u{2566}\u{2550}\u{2550}\u{2550}\u{2557}"
        let lpBot = "\u{255A}\u{2550}\u{2550}\u{2550}\u{2569}\u{2550}\u{2550}\u{2550}\u{2569}\u{2550}\u{2550}\u{2550}\u{2569}\u{2550}\u{2550}\u{2550}\u{2569}\u{2550}\u{2550}\u{2550}\u{2569}\u{2550}\u{2550}\u{2550}\u{255D}"
        func lpFrame(_ content: String) -> String {
            let c = centered(content)
            return fl + String(repeating: " ", count: c.left) + styled(content, gd) + String(repeating: " ", count: c.right) + fl
        }

        // Letterpress middle: gold separators, bold white letters (25 visible)
        func lpMiddle() -> String {
            let c = centered("\u{2551} S \u{2551} A \u{2551} D \u{2551} D \u{2551} L \u{2551} E \u{2551}")
            let sep = styled("\u{2551}", gd)
            let cells = ["S", "A", "D", "D", "L", "E"].map {
                sep + styled(" \($0) ", .bold, .white)
            }.joined() + sep
            return fl + String(repeating: " ", count: c.left) + cells + String(repeating: " ", count: c.right) + fl
        }

        // Reward: ◆ REWARD ◆ (10 visible)
        func reward() -> String {
            let c = centered("\u{25C6} REWARD \u{25C6}")
            return fl
                + String(repeating: " ", count: c.left)
                + styled("\u{25C6}", gd) + styled(" REWARD ", .bold, .white) + styled("\u{25C6}", gd)
                + String(repeating: " ", count: c.right)
                + fl
        }

        let banner = [
            styled("\u{2554}\(bars)\u{2557}", fr),
            fl + styled(" \(dots) ", dk) + fl,
            empty(),
            fl + styled(pad("W \u{00B7} A \u{00B7} N \u{00B7} T \u{00B7} E \u{00B7} D"), .bold, gd) + fl,
            empty(),
            divider(),
            empty(),
            lpFrame(lpTop),
            lpMiddle(),
            lpFrame(lpBot),
            empty(),
            divider(),
            empty(),
            fl + styled(pad("repo wrangler"), tn) + fl,
            fl + styled(pad("v\(version)"), .dim) + fl,
            empty(),
            reward(),
            fl + styled(pad("a clean ~/Developer/"), .white) + fl,
            empty(),
            fl + styled(" \(dots) ", dk) + fl,
            styled("\u{255A}\(bars)\u{255D}", fr),
        ]

        print()
        for line in banner {
            print("  " + line)
        }

        let labelWidth = fields.map(\.0.count).max() ?? 0
        for item in fields {
            let padded = item.0.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            print("    " + styled(padded, .dim) + "  " + styled(item.1, .white))
        }
        print()
    }
}
