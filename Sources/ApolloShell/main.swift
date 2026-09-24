import Foundation
import ApolloBase

enum AppBanner {
    static let text = "ApolloShell \(ShellVersion.current)"
}

if CommandLine.arguments.contains("--render") {
    exit(MainActor.assumeIsolated { RenderCommand.run(CommandLine.arguments) })
}

if CommandLine.arguments.contains("--version") {
    print(AppBanner.text)
    exit(0)
}

exit(MainActor.assumeIsolated { LiveShell.run(CommandLine.arguments) })
