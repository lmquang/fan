import Foundation

enum SMCKey {
    static let fanCount = "FNum"
    static let forceBits = "FS! "
    static let forceTest = "Ftst"

    static func currentRPM(_ fanID: Int) -> String { "F\(fanID)Ac" }
    static func minimumRPM(_ fanID: Int) -> String { "F\(fanID)Mn" }
    static func maximumRPM(_ fanID: Int) -> String { "F\(fanID)Mx" }
    static func targetRPM(_ fanID: Int) -> String { "F\(fanID)Tg" }
    static func mode(_ fanID: Int) -> String { "F\(fanID)Md" }
    static func alternateMode(_ fanID: Int) -> String { "F\(fanID)md" }
    static func modeCandidates(_ fanID: Int) -> [String] { [mode(fanID), alternateMode(fanID)] }
    static func name(_ fanID: Int) -> String { "F\(fanID)ID" }
    static let temperatureCandidates = [
        "TC0P", "TC0E", "TC0F", "TC0D"
    ]
}
