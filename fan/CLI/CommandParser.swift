import Foundation

struct CommandParser {
    func parse(arguments: [String]) throws -> FanCommand {
        guard let command = arguments.first else {
            return .help
        }

        switch command {
        case "help", "--help", "-h":
            return .help
        case "status":
            return .status
        case "auto":
            return .auto
        case "max":
            return .max
        case "set":
            guard arguments.count == 2 else {
                throw FanControlError.invalidArguments("usage: fan set <percent>")
            }

            guard let percent = Int(arguments[1]) else {
                throw FanControlError.invalidArguments("percent must be an integer from 0 to 100")
            }

            guard (0...100).contains(percent) else {
                throw FanControlError.invalidArguments("percent must be between 0 and 100")
            }

            return .set(percent: percent)
        default:
            throw FanControlError.invalidArguments("unknown command '\(command)'")
        }
    }
}
