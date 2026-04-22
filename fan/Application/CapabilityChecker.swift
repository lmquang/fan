import Foundation

struct CapabilityChecker {
    func requireReadable(_ status: FanStatus) throws {
        guard status.capability.canReadFans, !status.fans.isEmpty else {
            throw FanControlError.noFansDetected
        }
    }

    func requireWritable(_ status: FanStatus) throws {
        guard status.isWritable else {
            throw FanControlError.capabilityUnavailable("fan control keys are not available on this machine")
        }

        if status.capability.requiresRoot && geteuid() != 0 {
            throw FanControlError.permissionDenied("fan writes require root privileges; try running with sudo")
        }
    }

    func requireAutoSupport(_ status: FanStatus) throws {
        guard status.capability.canSetAutoMode else {
            throw FanControlError.capabilityUnavailable("automatic fan mode is not available on this machine")
        }
    }
}
