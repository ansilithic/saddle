import os

enum Log {
    private static let logger = Logger(subsystem: "com.ansilithic.saddle", category: "general")

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
