import Foundation
import IOKit
import OSLog

final class SMCConnection {
    private let connection: io_connect_t
    private let logger = FanLogger.logger(.hardware)

    var serviceName: String {
        "AppleSMC"
    }

    init() throws {
        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }

        let matchResult = IOServiceGetMatchingServices(mainPort, IOServiceMatching("AppleSMC"), &iterator)
        guard matchResult == kIOReturnSuccess else {
            throw FanControlError.unsupportedHardware("failed to match AppleSMC: 0x\(String(matchResult, radix: 16))")
        }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            throw FanControlError.unsupportedHardware("AppleSMC service was not found")
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else {
            throw FanControlError.unsupportedHardware("failed to open AppleSMC: 0x\(String(openResult, radix: 16))")
        }

        self.connection = connection
        logger.debug("opened smc connection service=AppleSMC")
    }

    deinit {
        IOServiceClose(connection)
    }

    func read(_ key: String) throws -> SMCValue {
        logger.debug("reading smc key=\(key, privacy: .public)")

        let (input, keyInfoOutput) = try fetchKeyInfo(key)
        var readInput = input
        readInput.keyInfo.dataSize = keyInfoOutput.keyInfo.dataSize
        readInput.data8 = SMCCommand.readBytes.rawValue

        let readOutput = try callSMC(input: readInput)
        guard readOutput.result == SMCResultCode.success.rawValue else {
            throw FanControlError.keyNotFound("failed to read key '\(key)': smc result 0x\(String(readOutput.result, radix: 16))")
        }

        let bytes = bytes32Array(readOutput.bytes).prefix(Int(keyInfoOutput.keyInfo.dataSize))
        let dataType = (String(bytes: withUnsafeBytes(of: keyInfoOutput.keyInfo.dataType.bigEndian, Array.init), encoding: .ascii) ?? "????")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))

        return SMCValue(key: key, dataType: dataType, dataSize: Int(keyInfoOutput.keyInfo.dataSize), bytes: Data(bytes))
    }

    func readIfPresent(_ key: String) -> SMCValue? {
        try? read(key)
    }

    func write(_ key: String, dataType: String, bytes: Data) throws {
        logger.debug("writing smc key=\(key, privacy: .public) dataType=\(dataType, privacy: .public) byteCount=\(bytes.count, privacy: .public)")

        let (input, keyInfoOutput) = try fetchKeyInfo(key)
        var writeInput = input
        writeInput.data8 = SMCCommand.writeBytes.rawValue
        writeInput.keyInfo.dataSize = keyInfoOutput.keyInfo.dataSize
        writeInput.bytes = makeBytes32(bytes)

        let writeOutput = try callSMC(input: writeInput)
        guard writeOutput.result == SMCResultCode.success.rawValue else {
            throw FanControlError.writeRejected("failed to write key '\(key)': smc result 0x\(String(writeOutput.result, radix: 16))")
        }
    }

    func enumerateKeys() -> [String] {
        guard let keyCountValue = try? read("#KEY"), keyCountValue.bytes.count >= 4 else {
            return []
        }

        let keyCount = Int(keyCountValue.bytes.uint32(bigEndian: true))
        guard keyCount > 0 else {
            return []
        }

        var keys: [String] = []
        keys.reserveCapacity(keyCount)

        for index in 0..<keyCount {
            var input = SMCParamStruct()
            input.data8 = 8
            input.data32 = UInt32(index)

            guard let output = try? callSMC(input: input), output.result == SMCResultCode.success.rawValue else {
                continue
            }

            let key = fourCharCodeString(from: output.key)
            if !key.isEmpty {
                keys.append(key)
            }
        }

        return keys
    }

    private func fetchKeyInfo(_ key: String) throws -> (SMCParamStruct, SMCParamStruct) {
        var input = SMCParamStruct()
        input.key = try fourCharCode(from: key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        let output = try callSMC(input: input)
        guard output.result == SMCResultCode.success.rawValue else {
            throw FanControlError.keyNotFound("failed to read key info for '\(key)': smc result 0x\(String(output.result, radix: 16))")
        }

        return (input, output)
    }

    private func callSMC(input: SMCParamStruct) throws -> SMCParamStruct {
        var inp = SMCParamStruct()
        _ = withUnsafeMutableBytes(of: &inp) { memset($0.baseAddress!, 0, $0.count) }
        inp.key = input.key
        inp.data8 = input.data8
        inp.data32 = input.data32
        inp.keyInfo.dataSize = input.keyInfo.dataSize
        inp.bytes = input.bytes

        var out = SMCParamStruct()
        _ = withUnsafeMutableBytes(of: &out) { memset($0.baseAddress!, 0, $0.count) }
        var outSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &inp,
            MemoryLayout<SMCParamStruct>.stride,
            &out,
            &outSize
        )

        guard result == kIOReturnSuccess else {
            throw FanControlError.smcFailure("IOKit call failed: 0x\(String(result, radix: 16))")
        }

        return out
    }

    private func fourCharCode(from string: String) throws -> UInt32 {
        guard string.count == 4 else {
            throw FanControlError.invalidArguments("invalid SMC key '\(string)'")
        }

        return string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharCodeString(from value: UInt32) -> String {
        let scalars = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(decoding: scalars, as: UTF8.self)
    }
}
