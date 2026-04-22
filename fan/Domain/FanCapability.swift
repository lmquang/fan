import Foundation

struct FanCapability {
    let canReadFans: Bool
    let canSetTargetSpeed: Bool
    let canSetAutoMode: Bool
    let canSetManualMode: Bool
    let requiresRoot: Bool
    let notes: [String]

    static let unsupported = FanCapability(
        canReadFans: false,
        canSetTargetSpeed: false,
        canSetAutoMode: false,
        canSetManualMode: false,
        requiresRoot: true,
        notes: ["No supported fan control keys were detected."]
    )
}
