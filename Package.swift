// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ApolloShell",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "ApolloShellCore"),
        .testTarget(name: "ApolloShellCoreTests", dependencies: ["ApolloShellCore"]),
    ]
)
