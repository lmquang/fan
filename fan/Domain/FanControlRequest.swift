import Foundation

enum FanControlRequest {
    case auto
    case max
    case set(percent: Int)
}

struct FanTarget {
    let fanID: Int
    let rpm: Int
}
