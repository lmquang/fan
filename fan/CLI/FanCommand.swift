import Foundation

enum FanCommand: Equatable {
    case help
    case status
    case auto
    case max
    case set(percent: Int)
}
