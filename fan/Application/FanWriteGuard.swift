import Foundation
import OSLog

struct FanWriteGuard {
    private let logger = FanLogger.logger(.application)

    func targetsForMax(status: FanStatus) throws -> [FanTarget] {
        logger.debug("building max rpm targets fanCount=\(status.fans.count, privacy: .public)")
        return status.fans.map { FanTarget(fanID: $0.id, rpm: $0.maxRPM) }
    }

    func targets(forPercent percent: Int, status: FanStatus) throws -> [FanTarget] {
        logger.debug("building manual targets percent=\(percent, privacy: .public) fanCount=\(status.fans.count, privacy: .public)")
        guard (0...100).contains(percent) else {
            throw FanControlError.invalidArguments("percent must be between 0 and 100")
        }

        return status.fans.map { fan in
            let requestedRPM = Int((Double(fan.maxRPM) * Double(percent) / 100.0).rounded())
            let clampedRPM = max(fan.minRPM, min(fan.maxRPM, requestedRPM))
            return FanTarget(fanID: fan.id, rpm: clampedRPM)
        }
    }
}
