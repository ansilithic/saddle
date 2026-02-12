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
        if let authenticatedUser { fields.append(("GitHub", authenticatedUser)) }

        let title = "s a d d l e"
        let version = Saddle.configuration.version
        let tagline = "A personal package manager for your repos."
        let grad = ["\u{2591}\u{2591}\u{2592}\u{2592}\u{2593}\u{2593}\u{2588}\u{2588}", "\u{2588}\u{2588}\u{2593}\u{2593}\u{2592}\u{2592}\u{2591}\u{2591}"]
        let banner = styled(grad[0], .cyan) + styled("  \(title)  ", .bold) + styled(grad[1], .cyan) + "  " + styled("v\(version)", .dim)

        print()
        print("  " + banner)
        print("  " + styled(tagline, .dim))
        print()

        let labelWidth = fields.map(\.0.count).max() ?? 0
        for item in fields {
            let padded = item.0.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            print("   " + styled(padded, .dim) + "  " + styled(item.1, .white))
        }
        print()
    }
}
