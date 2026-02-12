import Foundation

struct Exec {
    @discardableResult
    static func run(_ executable: String, args: [String], cwd: String? = nil, env: [String: String]? = nil) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = nil

        if let cwd = cwd {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        if let env = env {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env {
                environment[key] = value
            }
            task.environment = environment
        }

        do {
            try task.run()
        } catch {
            return ("", 1)
        }

        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (output, task.terminationStatus)
    }

    @discardableResult
    static func git(_ args: String..., at path: String) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", path] + args
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = nil

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        task.environment = environment

        do { try task.run() } catch { return ("", 1) }
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, task.terminationStatus)
    }
}
