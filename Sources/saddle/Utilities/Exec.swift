import Foundation

struct Exec {
    @discardableResult
    static func run(_ executable: String, args: [String], cwd: String? = nil, env: [String: String]? = nil, timeout: TimeInterval? = nil) -> (output: String, exitCode: Int32) {
        execute(
            executable: executable,
            args: args,
            cwd: cwd,
            env: env,
            mergeStderr: true,
            timeout: timeout
        )
    }

    @discardableResult
    static func git(_ args: String..., at path: String, timeout: TimeInterval? = nil) -> (output: String, exitCode: Int32) {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        return execute(
            executable: "/usr/bin/git",
            args: ["-C", path] + args,
            cwd: nil,
            env: env,
            mergeStderr: false,
            timeout: timeout
        )
    }

    private static func execute(
        executable: String,
        args: [String],
        cwd: String?,
        env: [String: String]?,
        mergeStderr: Bool,
        timeout: TimeInterval?
    ) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = pipe
        task.standardError = mergeStderr ? pipe : FileHandle.nullDevice
        task.standardInput = nil

        if let cwd {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        if let env {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env { environment[key] = value }
            task.environment = environment
        }

        do { try task.run() } catch { return ("", 1) }

        var timedOut = false
        var timeoutWorkItem: DispatchWorkItem?

        if let timeout {
            let pid = task.processIdentifier
            let item = DispatchWorkItem {
                timedOut = true
                kill(pid, SIGKILL)
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
