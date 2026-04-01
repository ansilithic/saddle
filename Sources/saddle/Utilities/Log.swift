#if canImport(os)
import os
#endif
import Foundation

enum Log {
    static func error(_ message: String) {
        #if canImport(os)
        let logger = Logger(subsystem: "com.ansilithic.saddle", category: "general")
        logger.error("\(message, privacy: .public)")
        #else
        fputs("error: \(message)\n", stderr)
        #endif
    }

    static func info(_ message: String) {
        #if canImport(os)
        let logger = Logger(subsystem: "com.ansilithic.saddle", category: "general")
        logger.info("\(message, privacy: .public)")
        #else
        fputs("info: \(message)\n", stderr)
        #endif
    }
}
