import Foundation

struct Log {
    static func error(_ message: String) {
        let dir = Config.stateDir
        if !FS.isDirectory(dir) { _ = FS.createDirectory(dir) }

        let timestamp = DateFormatting.iso8601.string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"

        let path = Config.logFile
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) { handle.write(data) }
            handle.closeFile()
        } else {
            _ = FS.writeFile(path, contents: entry)
        }
    }
}
