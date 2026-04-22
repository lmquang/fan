import Foundation
import OSLog

struct FanControllerService {
    let hardware: HardwareAccessing
    let statusService: FanStatusService
    let writeGuard: FanWriteGuard
    let capabilityChecker: CapabilityChecker
    private let logger = FanLogger.logger(.application)

    func status() throws -> FanStatus {
        try statusService.readStatus()
    }

    func apply(request: FanControlRequest) throws -> FanStatus {
        logger.debug("applying fan control request")
        let status = try statusService.readStatus()
        try capabilityChecker.requireWritable(status)

        switch request {
        case .auto:
            try capabilityChecker.requireAutoSupport(status)
            try hardware.setAutomaticControl(for: status.fans)
        case .max:
            let targets = try writeGuard.targetsForMax(status: status)
            try hardware.setManualTargets(targets, basedOn: status)
        case let .set(percent):
            let targets = try writeGuard.targets(forPercent: percent, status: status)
            try hardware.setManualTargets(targets, basedOn: status)
        }

        return try statusService.readStatus()
    }
}
