import Foundation
import OSLog

struct FanCLI {
    private let parser = CommandParser()
    private let formatter = OperationResultFormatter()
    private let logger = FanLogger.logger(.cli)
    private let controllerService = FanControllerService(
        hardware: SMCFanController(),
        statusService: FanStatusService(hardware: SMCFanController()),
        writeGuard: FanWriteGuard(),
        capabilityChecker: CapabilityChecker()
    )

    func run(arguments: [String]) -> Int32 {
        logger.debug("received cli arguments count=\(arguments.count, privacy: .public)")

        do {
            let command = try parser.parse(arguments: arguments)
            switch command {
            case .help:
                print(UsageRenderer().render())
                return 0
            case .status:
                let status = try controllerService.status()
                print(formatter.render(status: status))
                return 0
            case .auto:
                let status = try controllerService.apply(request: .auto)
                print(formatter.render(action: "Set automatic fan control", status: status))
                return 0
            case .max:
                let status = try controllerService.apply(request: .max)
                print(formatter.render(action: "Forced maximum fan speed", status: status))
                return 0
            case let .set(percent):
                let status = try controllerService.apply(request: .set(percent: percent))
                print(formatter.render(action: "Set fan speed to \(percent)% of max RPM", status: status))
                return 0
            }
        } catch let error as FanControlError {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            if case .invalidArguments = error {
                FileHandle.standardError.write(Data((UsageRenderer().render() + "\n").utf8))
                return 2
            }
            return 1
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
