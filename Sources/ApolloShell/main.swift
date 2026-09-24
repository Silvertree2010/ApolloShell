import ApolloBase

enum AppBanner {
    static let text = "ApolloShell \(ShellVersion.current)"
}

print(AppBanner.text)
