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

        let temperatures = readTemperatures(using: connection)
        let cpuTemperatureCelsius = representativeTemperature(from: temperatures, prefixes: ["TC", "Tp", "Te"])
        let gpuTemperatureCelsius = representativeTemperature(from: temperatures, prefixes: ["TG", "Tg"])
        let capability = buildCapability(fans: fans, connection: connection)
        return FanStatus(
            serviceName: connection.serviceName,
            fans: fans,
            temperatureCelsius: cpuTemperatureCelsius,
            cpuTemperatureCelsius: cpuTemperatureCelsius,
            gpuTemperatureCelsius: gpuTemperatureCelsius,
            temperatures: temperatures,
            capability: capability
        )
    }

    func setAutomaticControl(for fans: [FanDescriptor]) throws {
        let connection = try SMCConnection()
        logger.debug("setting automatic control fans=\(fans.count, privacy: .public)")

        if let forceValue = connection.readIfPresent(SMCKey.forceBits) {
            let bytes = try SMCDataCoder.encodeUInt(0, dataType: forceValue.dataType)
            try? connection.write(SMCKey.forceBits, dataType: forceValue.dataType, bytes: bytes)
        }

        try executeWithFtstUnlock(
            connection: connection,
            failureMessage: "automatic fan mode was rejected and Ftst unlock is not available"
        ) {
            try setAutomaticMode(for: fans, connection: connection)
        }

        if let forceTestValue = connection.readIfPresent(SMCKey.forceTest) {
            let bytes = try SMCDataCoder.encodeUInt(0, dataType: forceTestValue.dataType)
            try? connection.write(SMCKey.forceTest, dataType: forceTestValue.dataType, bytes: bytes)
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

    private func readTemperatures(using connection: SMCConnection) -> [TemperatureSensor] {
        var sensorValues: [String: Double] = [:]

        for key in SMCKey.temperatureCandidates {
            if let value = connection.readIfPresent(key).flatMap(SMCDataCoder.decodeTemperature), isLikelyTemperature(value) {
                sensorValues[key] = value
            }
        }

        if let keyPattern = try? NSRegularExpression(pattern: #"^T[A-Za-z0-9]{3}$"#) {
            for key in connection.enumerateKeys() {
                let range = NSRange(location: 0, length: key.utf16.count)
                guard keyPattern.firstMatch(in: key, options: [], range: range) != nil,
                      !key.hasSuffix("c"),
                      !key.hasSuffix("C") else {
                    continue
                }

                if let value = connection.readIfPresent(key).flatMap(SMCDataCoder.decodeTemperature), isLikelyTemperature(value) {
                    sensorValues[key] = value
                }
            }
        }

        let temperatures = sensorValues.keys.sorted().compactMap { key in
            sensorValues[key].map { TemperatureSensor(key: key, celsius: $0) }
        }

        logger.debug("resolved readable temperature sensors count=\(temperatures.count, privacy: .public)")
        return temperatures
    }

    private func representativeTemperature(from temperatures: [TemperatureSensor], prefixes: [String]) -> Double? {
        let samples = temperatures
            .filter { sensor in prefixes.contains(where: { sensor.key.hasPrefix($0) }) }
            .map(\.celsius)

        guard !samples.isEmpty else {
            return nil
        }
        return medianValue(samples)
    }

    private func isLikelyTemperature(_ value: Double) -> Bool {
        (10.0...120.0).contains(value)
    }

    private func medianValue(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
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
        try executeWithFtstUnlock(
            connection: connection,
            failureMessage: "manual fan mode was rejected and Ftst unlock is not available"
        ) {
            try setManualMode(for: targets, connection: connection)
        }
    }

    private func executeWithFtstUnlock(
        connection: SMCConnection,
        failureMessage: String,
        action: () throws -> Void
    ) throws {
        do {
            try action()
            return
        } catch {
            logger.debug("direct mode write failed; attempting Ftst unlock error=\(error.localizedDescription, privacy: .public)")
        }

        guard let forceTestValue = connection.readIfPresent(SMCKey.forceTest) else {
            throw FanControlError.writeRejected(failureMessage)
        }

        let unlockBytes = try SMCDataCoder.encodeUInt(1, dataType: forceTestValue.dataType)
        try connection.write(SMCKey.forceTest, dataType: forceTestValue.dataType, bytes: unlockBytes)

        let deadline = DispatchTime.now().uptimeNanoseconds + unlockTimeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            do {
                try action()
                return
            } catch {
                logger.debug("mode write retry still blocked error=\(error.localizedDescription, privacy: .public)")
                Thread.sleep(forTimeInterval: Double(unlockPollIntervalNanoseconds) / 1_000_000_000)
            }
        }

        throw FanControlError.writeRejected("timed out waiting for Ftst unlock to allow mode write")
    }

    private func setAutomaticMode(for fans: [FanDescriptor], connection: SMCConnection) throws {
        for fan in fans {
            var lastError: Error?
            var wroteMode = false

            for key in SMCKey.modeCandidates(fan.id) {
                guard let modeValue = connection.readIfPresent(key) else {
                    continue
                }

                do {
                    let bytes = try SMCDataCoder.encodeUInt(0, dataType: modeValue.dataType)
                    try connection.write(key, dataType: modeValue.dataType, bytes: bytes)
                    wroteMode = true
                    break
                } catch {
                    lastError = error
                }
            }

            if wroteMode {
                continue
            }

            if let lastError {
                throw lastError
            }

            throw FanControlError.capabilityUnavailable("fan \(fan.id) does not expose a mode key")
        }
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
