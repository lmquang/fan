import Foundation

struct FanDescriptor {
    let id: Int
    let name: String
    let currentRPM: Int
    let minRPM: Int
    let maxRPM: Int
    let targetRPM: Int?
    let mode: FanMode
}

struct FanStatus {
    let serviceName: String
    let fans: [FanDescriptor]
    let capability: FanCapability

    var isWritable: Bool {
        capability.canSetTargetSpeed || capability.canSetAutoMode
    }
}
