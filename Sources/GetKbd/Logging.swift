import OSLog

enum GetKbdLog {
    private static let logger = Logger(subsystem: "com.getkbd.app", category: "getkbd")

    static func event(_ name: String, _ message: String = "") {
        if message.isEmpty {
            logger.notice("\(name, privacy: .public)")
        } else {
            logger.notice("\(name, privacy: .public): \(message, privacy: .public)")
        }
    }

    static func error(_ name: String, _ message: String) {
        logger.error("\(name, privacy: .public): \(message, privacy: .public)")
    }
}
