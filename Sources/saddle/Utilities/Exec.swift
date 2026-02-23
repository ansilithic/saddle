import Foundation

struct Exec {
    @discardableResult
    static func run(_ executable: String, args: [String], cwd: String? = nil, env: [String: String]? = nil, timeout: TimeInterval? = nil) -> (output: String, exitCode: Int32) {
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

        var timedOut = false
        var timeoutWorkItem: DispatchWorkItem?

        if let timeout = timeout {
            let item = DispatchWorkItem {
                timedOut = true
                task.terminate()
            }
            timeoutWorkItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        timeoutWorkItem?.cancel()

        if timedOut {
            return ("timed out after \(Int(timeout!))s", 124)
        }

        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (output, task.terminationStatus)
    }

    @discardableResult
    static func git(_ args: String..., at path: String, timeout: TimeInterval? = nil) -> (output: String, exitCode: Int32) {
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

        var timedOut = false
        var timeoutWorkItem: DispatchWorkItem?

        if let timeout = timeout {
            let item = DispatchWorkItem {
                timedOut = true
                task.terminate()
            }
            timeoutWorkItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        timeoutWorkItem?.cancel()

        if timedOut {
            return ("timed out after \(Int(timeout!))s", 124)
        }

        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, task.terminationStatus)
    }
}
