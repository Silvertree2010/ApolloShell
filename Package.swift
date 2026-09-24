// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ApolloShell",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "apollowm-probe", targets: ["apollowm-probe"]),
    ],
    targets: [
        .target(name: "ApolloShellCore"),
        .target(name: "ApolloWMCore"),
        .target(name: "ApolloWM", dependencies: ["ApolloWMCore"]),
        .executableTarget(name: "apollowm-probe", dependencies: ["ApolloWM"]),
        .testTarget(name: "ApolloShellCoreTests", dependencies: ["ApolloShellCore"]),
        .testTarget(name: "ApolloWMCoreTests", dependencies: ["ApolloWMCore"]),
    ]
)
