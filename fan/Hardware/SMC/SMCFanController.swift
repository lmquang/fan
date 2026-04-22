import Foundation
import OSLog

final class SMCFanController: HardwareAccessing {
    private let logger = FanLogger.logger(.hardware)
    private let unlockTimeoutNanoseconds: UInt64 = 10_000_000_000
    private let unlockPollIntervalNanoseconds: UInt64 = 100_000_000

    func readStatus() throws -> FanStatus {
        let connection = try SMCConnection()
        let forceBits = connection.readIfPresent(SMCKey.forceBits).flatMap(SMCDataCoder.decodeUInt)
        let fanIDs = resolvedFanIDs(using: connection)
        logger.debug("resolved fan ids count=\(fanIDs.count, privacy: .public) ids=\(fanIDs.map(String.init).joined(separator: ","), privacy: .public)")

        let fans = fanIDs.compactMap { fanID in
            readFanDescriptor(fanID: fanID, connection: connection, forceBits: forceBits)
        }

        guard !fans.isEmpty else {
            throw FanControlError.noFansDetected
        }

        let capability = buildCapability(fans: fans, connection: connection)
        return FanStatus(serviceName: connection.serviceName, fans: fans, capability: capability)
    }

    func setAutomaticControl(for fans: [FanDescriptor]) throws {
        let connection = try SMCConnection()
        logger.debug("setting automatic control fans=\(fans.count, privacy: .public)")

        if let forceValue = connection.readIfPresent(SMCKey.forceBits) {
            let bytes = try SMCDataCoder.encodeUInt(0, dataType: forceValue.dataType)
            try connection.write(SMCKey.forceBits, dataType: forceValue.dataType, bytes: bytes)
        }

        for fan in fans {
            if let modeKey = resolvedModeKey(fanID: fan.id, connection: connection), let modeValue = connection.readIfPresent(modeKey) {
                let bytes = try SMCDataCoder.encodeUInt(0, dataType: modeValue.dataType)
                try connection.write(modeKey, dataType: modeValue.dataType, bytes: bytes)
            }
        }

        if let forceTestValue = connection.readIfPresent(SMCKey.forceTest) {
            let bytes = try SMCDataCoder.encodeUInt(0, dataType: forceTestValue.dataType)
            try connection.write(SMCKey.forceTest, dataType: forceTestValue.dataType, bytes: bytes)
        }
    }

    func setManualTargets(_ targets: [FanTarget], basedOn status: FanStatus) throws {
        let connection = try SMCConnection()
        logger.debug("setting manual targets targetCount=\(targets.count, privacy: .public)")

        if let forceValue = connection.readIfPresent(SMCKey.forceBits) {
            let forceMask = targets.reduce(0) { partial, target in partial | (1 << target.fanID) }
            let bytes = try SMCDataCoder.encodeUInt(forceMask, dataType: forceValue.dataType)
            try? connection.write(SMCKey.forceBits, dataType: forceValue.dataType, bytes: bytes)
        }

        try prepareManualControl(targets: targets, connection: connection)

        for target in targets {
            let fan = status.fans.first(where: { $0.id == target.fanID })
            guard let targetValue = connection.readIfPresent(SMCKey.targetRPM(target.fanID)) else {
                throw FanControlError.capabilityUnavailable("fan \(target.fanID) does not expose a writable target RPM key")
            }

            let bytes = try SMCDataCoder.encodeRPM(target.rpm, dataType: targetValue.dataType)
            logger.debug("writing target fanID=\(target.fanID, privacy: .public) rpm=\(target.rpm, privacy: .public) currentMax=\(fan?.maxRPM ?? 0, privacy: .public)")
            try connection.write(SMCKey.targetRPM(target.fanID), dataType: targetValue.dataType, bytes: bytes)
        }
    }

    private func resolvedFanIDs(using connection: SMCConnection) -> [Int] {
        if let countValue = connection.readIfPresent(SMCKey.fanCount), let count = SMCDataCoder.decodeUInt(countValue), count > 0 {
            return Array(0..<count)
        }

        var ids = Set<Int>()
        for fanID in 0..<8 {
            if connection.readIfPresent(SMCKey.currentRPM(fanID)) != nil || connection.readIfPresent(SMCKey.maximumRPM(fanID)) != nil {
                ids.insert(fanID)
            }
        }

        if ids.isEmpty {
            let pattern = try? NSRegularExpression(pattern: #"^F(\d+)(Ac|Mn|Mx|Tg|Md|md)$"#)
            for key in connection.enumerateKeys() {
                guard let pattern else { continue }
                let range = NSRange(location: 0, length: key.utf16.count)
                guard let match = pattern.firstMatch(in: key, options: [], range: range), match.numberOfRanges > 1,
                      let idRange = Range(match.range(at: 1), in: key), let fanID = Int(key[idRange]) else {
                    continue
                }
                ids.insert(fanID)
            }
        }

        return ids.sorted()
    }

    private func readFanDescriptor(fanID: Int, connection: SMCConnection, forceBits: Int?) -> FanDescriptor? {
        guard let currentValue = connection.readIfPresent(SMCKey.currentRPM(fanID)) ?? connection.readIfPresent(SMCKey.maximumRPM(fanID)) else {
            return nil
        }

        let currentRPM = SMCDataCoder.decodeRPM(connection.readIfPresent(SMCKey.currentRPM(fanID)) ?? currentValue) ?? 0
        let minRPM = SMCDataCoder.decodeRPM(connection.readIfPresent(SMCKey.minimumRPM(fanID)) ?? currentValue) ?? 0
        let maxRPM = SMCDataCoder.decodeRPM(connection.readIfPresent(SMCKey.maximumRPM(fanID)) ?? currentValue) ?? currentRPM
        let targetRPM = connection.readIfPresent(SMCKey.targetRPM(fanID)).flatMap(SMCDataCoder.decodeRPM)
        let name = connection.readIfPresent(SMCKey.name(fanID)).flatMap(SMCDataCoder.decodeString) ?? "Fan \(fanID)"

        let mode: FanMode
        if let modeValue = readModeValue(fanID: fanID, connection: connection) {
            mode = modeValue == 0 ? .automatic : .manual
        } else if let forceBits, (forceBits & (1 << fanID)) != 0 {
            mode = .manual
        } else {
            mode = .unknown
        }

        return FanDescriptor(
            id: fanID,
            name: name,
            currentRPM: currentRPM,
            minRPM: minRPM,
            maxRPM: maxRPM,
            targetRPM: targetRPM,
            mode: mode
        )
    }

    private func buildCapability(fans: [FanDescriptor], connection: SMCConnection) -> FanCapability {
        let hasTarget = fans.contains { connection.readIfPresent(SMCKey.targetRPM($0.id)) != nil }
        let hasMode = fans.contains { resolvedModeKey(fanID: $0.id, connection: connection) != nil }
        let hasForceBits = connection.readIfPresent(SMCKey.forceBits) != nil
        let hasForceTest = connection.readIfPresent(SMCKey.forceTest) != nil

        var notes: [String] = []
        if !hasTarget {
            notes.append("Target RPM keys were not detected.")
        }
        if !hasMode && !hasForceBits && !hasForceTest {
            notes.append("Auto/manual mode keys were not detected.")
        }
        if hasForceTest {
            notes.append("Ftst diagnostic unlock is available.")
        }

        return FanCapability(
            canReadFans: !fans.isEmpty,
            canSetTargetSpeed: hasTarget,
            canSetAutoMode: hasMode || hasForceBits || hasForceTest,
            canSetManualMode: hasMode || hasForceBits || hasForceTest,
            requiresRoot: true,
            notes: notes
        )
    }

    private func resolvedModeKey(fanID: Int, connection: SMCConnection) -> String? {
        for key in SMCKey.modeCandidates(fanID) where connection.readIfPresent(key) != nil {
            return key
        }
        return nil
    }

    private func readModeValue(fanID: Int, connection: SMCConnection) -> Int? {
        for key in SMCKey.modeCandidates(fanID) {
            if let value = connection.readIfPresent(key).flatMap(SMCDataCoder.decodeUInt) {
                return value
            }
        }
        return nil
    }

    private func prepareManualControl(targets: [FanTarget], connection: SMCConnection) throws {
        do {
            try setManualMode(for: targets, connection: connection)
            return
        } catch {
            logger.debug("direct manual mode write failed; attempting Ftst unlock error=\(error.localizedDescription, privacy: .public)")
        }

        guard let forceTestValue = connection.readIfPresent(SMCKey.forceTest) else {
            throw FanControlError.writeRejected("manual fan mode was rejected and Ftst unlock is not available")
        }

        let unlockBytes = try SMCDataCoder.encodeUInt(1, dataType: forceTestValue.dataType)
        try connection.write(SMCKey.forceTest, dataType: forceTestValue.dataType, bytes: unlockBytes)

        let deadline = DispatchTime.now().uptimeNanoseconds + unlockTimeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            do {
                try setManualMode(for: targets, connection: connection)
                return
            } catch {
                logger.debug("manual mode retry still blocked error=\(error.localizedDescription, privacy: .public)")
                Thread.sleep(forTimeInterval: Double(unlockPollIntervalNanoseconds) / 1_000_000_000)
            }
        }

        throw FanControlError.writeRejected("timed out waiting for Ftst unlock to allow manual fan mode")
    }

    private func setManualMode(for targets: [FanTarget], connection: SMCConnection) throws {
        for target in targets {
            guard let modeKey = resolvedModeKey(fanID: target.fanID, connection: connection), let modeValue = connection.readIfPresent(modeKey) else {
                throw FanControlError.capabilityUnavailable("fan \(target.fanID) does not expose a mode key")
            }

            let bytes = try SMCDataCoder.encodeUInt(1, dataType: modeValue.dataType)
            try connection.write(modeKey, dataType: modeValue.dataType, bytes: bytes)
        }
    }
}
