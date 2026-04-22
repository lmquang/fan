import Foundation

struct OperationResultFormatter {
    func render(status: FanStatus) -> String {
        var lines: [String] = []
        lines.append("Service: \(status.serviceName)")
        lines.append("Fans: \(status.fans.count)")
        lines.append("Writable: \(status.isWritable ? "yes" : "no")")

        if !status.capability.notes.isEmpty {
            lines.append("Notes:")
            lines.append(contentsOf: status.capability.notes.map { "  - \($0)" })
        }

        for fan in status.fans {
            var line = "[\(fan.id)] \(fan.name): current=\(fan.currentRPM) RPM min=\(fan.minRPM) RPM max=\(fan.maxRPM) RPM mode=\(fan.mode.rawValue)"
            if let targetRPM = fan.targetRPM {
                line += " target=\(targetRPM) RPM"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    func render(action: String, status: FanStatus) -> String {
        [action, render(status: status)].joined(separator: "\n")
    }
}
