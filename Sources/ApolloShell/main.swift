import Foundation
import ApolloBase

enum AppBanner {
    static let text = "ApolloShell \(ShellVersion.current)"
}

if CommandLine.arguments.contains("--render") {
    exit(MainActor.assumeIsolated { RenderCommand.run(CommandLine.arguments) })
}

print(AppBanner.text)
