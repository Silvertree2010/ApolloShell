import Foundation
import ApolloBase
import ApolloConfig

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "check" {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let result = CheckCommand.run(
        arguments: Array(arguments.dropFirst()),
        environment: ProcessInfo.processInfo.environment,
        fileSystem: DiskFileSystem(),
        executableURL: executable
    )
    if !result.output.isEmpty {
        print(result.output)
    }
    exit(result.exitCode)
}
print("apollo \(ShellVersion.current)")
