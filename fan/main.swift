import Foundation

let cli = FanCLI()
let exitCode = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
