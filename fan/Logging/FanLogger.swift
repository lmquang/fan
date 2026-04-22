import Foundation
import OSLog

enum FanLogger {
    static func logger(_ context: LogContext) -> Logger {
        Logger(subsystem: "fan", category: context.rawValue)
    }
}
