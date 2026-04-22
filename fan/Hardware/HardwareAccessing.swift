import Foundation

protocol HardwareAccessing {
    func readStatus() throws -> FanStatus
    func setAutomaticControl(for fans: [FanDescriptor]) throws
    func setManualTargets(_ targets: [FanTarget], basedOn status: FanStatus) throws
}
