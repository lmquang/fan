import Foundation
import OSLog

struct FanStatusService {
    let hardware: HardwareAccessing
    private let capabilityChecker = CapabilityChecker()
    private let logger = FanLogger.logger(.application)

    func readStatus() throws -> FanStatus {
        logger.debug("reading fan status")
        let status = try hardware.readStatus()
        try capabilityChecker.requireReadable(status)
        return status
    }
}
