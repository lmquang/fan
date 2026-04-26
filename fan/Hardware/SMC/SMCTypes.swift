import Foundation

struct SMCValue {
    let key: String
    let dataType: String
    let dataSize: Int
    let bytes: Data
}

enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case writeBytes = 6
    case readKeyInfo = 9
}

enum SMCResultCode: UInt8 {
    case success = 0x00
}

struct SMCParamStruct {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = makeBytes32(Data())
}

enum SMCDataCoder {
    static func decodeUInt(_ value: SMCValue) -> Int? {
        switch value.dataType {
        case "ui8":
            return value.bytes.first.map(Int.init)
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            return Int(value.bytes.uint16(bigEndian: true))
        case "ui32":
            guard value.bytes.count >= 4 else { return nil }
            return Int(value.bytes.uint32(bigEndian: true))
        default:
            return nil
        }
    }

    static func decodeRPM(_ value: SMCValue) -> Int? {
        switch value.dataType {
        case "fpe2":
            guard value.bytes.count >= 2 else { return nil }
            let raw = value.bytes.uint16(bigEndian: true)
            return Int(Double(raw) / 4.0)
        case "flt":
            guard value.bytes.count >= 4 else { return nil }
            let raw = value.bytes.uint32(bigEndian: false)
            return Int(Float(bitPattern: raw).rounded())
        case "ui16", "ui32", "ui8":
            return decodeUInt(value)
        default:
            return nil
        }
    }

    static func decodeString(_ value: SMCValue) -> String? {
        String(data: value.bytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .nilIfEmpty
    }

    static func decodeTemperature(_ value: SMCValue) -> Double? {
        switch value.dataType {
        case "sp78":
            guard value.bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: value.bytes.uint16(bigEndian: true))
            return Double(raw) / 256.0
        case "flt":
            guard value.bytes.count >= 4 else { return nil }
            let raw = value.bytes.uint32(bigEndian: false)
            return Double(Float(bitPattern: raw))
        case "fpe2":
            guard value.bytes.count >= 2 else { return nil }
            let raw = value.bytes.uint16(bigEndian: true)
            return Double(raw) / 4.0
        default:
            return nil
        }
    }

    static func encodeRPM(_ rpm: Int, dataType: String) throws -> Data {
        switch dataType {
        case "fpe2":
            return Data.uint16(UInt16(clamping: rpm * 4), bigEndian: true)
        case "flt":
            return Data.uint32(Float(rpm).bitPattern, bigEndian: false)
        case "ui8":
            return Data([UInt8(clamping: rpm)])
        case "ui16":
            return Data.uint16(UInt16(clamping: rpm), bigEndian: true)
        case "ui32":
            return Data.uint32(UInt32(clamping: rpm), bigEndian: true)
        default:
            throw FanControlError.writeRejected("unsupported RPM data type '\(dataType)'")
        }
    }

    static func encodeUInt(_ value: Int, dataType: String) throws -> Data {
        switch dataType {
        case "ui8":
            return Data([UInt8(clamping: value)])
        case "ui16":
            return Data.uint16(UInt16(clamping: value), bigEndian: true)
        case "ui32":
            return Data.uint32(UInt32(clamping: value), bigEndian: true)
        default:
            throw FanControlError.writeRejected("unsupported integer data type '\(dataType)'")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Data {
    func uint16(bigEndian: Bool) -> UInt16 {
        var value: UInt16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { copyBytes(to: $0) }
        return bigEndian ? UInt16(bigEndian: value) : UInt16(littleEndian: value)
    }

    func uint32(bigEndian: Bool) -> UInt32 {
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { copyBytes(to: $0) }
        return bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
    }

    static func uint16(_ value: UInt16, bigEndian: Bool) -> Data {
        var raw = bigEndian ? value.bigEndian : value.littleEndian
        return Swift.withUnsafeBytes(of: &raw) { Data($0) }
    }

    static func uint32(_ value: UInt32, bigEndian: Bool) -> Data {
        var raw = bigEndian ? value.bigEndian : value.littleEndian
        return Swift.withUnsafeBytes(of: &raw) { Data($0) }
    }
}

func makeBytes32(_ data: Data) -> SMCParamStruct.Bytes32 {
    let padded = Array(data.prefix(32)) + Array(repeating: 0, count: max(0, 32 - data.count))
    return (
        padded[0], padded[1], padded[2], padded[3],
        padded[4], padded[5], padded[6], padded[7],
        padded[8], padded[9], padded[10], padded[11],
        padded[12], padded[13], padded[14], padded[15],
        padded[16], padded[17], padded[18], padded[19],
        padded[20], padded[21], padded[22], padded[23],
        padded[24], padded[25], padded[26], padded[27],
        padded[28], padded[29], padded[30], padded[31]
    )
}

func bytes32Array(_ value: SMCParamStruct.Bytes32) -> [UInt8] {
    [
        value.0, value.1, value.2, value.3, value.4, value.5, value.6, value.7,
        value.8, value.9, value.10, value.11, value.12, value.13, value.14, value.15,
        value.16, value.17, value.18, value.19, value.20, value.21, value.22, value.23,
        value.24, value.25, value.26, value.27, value.28, value.29, value.30, value.31,
    ]
}
