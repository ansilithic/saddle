import Foundation

struct Config {
    static var configDir: String { FS.expandPath("~/.config/saddle") }
    static var hooksDir: String { "\(configDir)/hooks" }
    static var stateDir: String { FS.expandPath("~/.local/state/saddle") }

    static var manifestPath: String { "\(configDir)/manifest.txt" }
    static var stateFile: String { "\(stateDir)/state.json" }
    static var logFile: String { "\(stateDir)/saddle.log" }
    static var hookLogsDir: String { "\(stateDir)/hooks" }
}
