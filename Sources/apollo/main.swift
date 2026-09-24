import Foundation
import ApolloBase
import ApolloConfig
import ApolloControl

let environment = ProcessInfo.processInfo.environment
let socketPath = ControlSocketPath.resolve(environment: environment, home: FileManager.default.homeDirectoryForCurrentUser)
let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
let cli = ApolloCLI(
    version: ShellVersion.current,
    transport: SocketTransport(path: socketPath),
    check: { arguments in
        CheckCommand.run(
            arguments: arguments,
            environment: environment,
            fileSystem: DiskFileSystem(),
            executableURL: executable
        )
    }
)
let code = cli.run(
    Array(CommandLine.arguments.dropFirst()),
    out: { text in
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    },
    err: { text in
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
)
exit(code)
