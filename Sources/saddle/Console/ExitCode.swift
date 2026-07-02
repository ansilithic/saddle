#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation

/// Standard exit codes for CLI tools.
public enum CLIExitCode: Int32, Sendable {
    case success = 0
    case warning = 1
    case error = 2

    /// Terminate the process with this exit code.
    public func exit() -> Never {
        _exit(rawValue)
    }
}
