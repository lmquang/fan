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

struct TemperatureSensor {
    let key: String
    let celsius: Double
}

struct FanStatus {
    let serviceName: String
    let fans: [FanDescriptor]
    let temperatureCelsius: Double?
    let cpuTemperatureCelsius: Double?
    let gpuTemperatureCelsius: Double?
    let temperatures: [TemperatureSensor]
    let capability: FanCapability

    var isWritable: Bool {
        capability.canSetTargetSpeed || capability.canSetAutoMode
    }
}
