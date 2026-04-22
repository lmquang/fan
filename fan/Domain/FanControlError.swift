import Foundation

enum FanControlError: LocalizedError {
    case invalidArguments(String)
    case unsupportedHardware(String)
    case permissionDenied(String)
    case capabilityUnavailable(String)
    case noFansDetected
    case keyNotFound(String)
    case smcFailure(String)
    case writeRejected(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message),
             let .unsupportedHardware(message),
             let .permissionDenied(message),
             let .capabilityUnavailable(message),
             let .keyNotFound(message),
             let .smcFailure(message),
             let .writeRejected(message):
            return message
        case .noFansDetected:
            return "no fans were detected through the SMC interface"
        }
    }
}
