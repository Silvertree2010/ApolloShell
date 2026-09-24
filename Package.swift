// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ApolloShell",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ApolloShell", targets: ["ApolloShell"]),
        .executable(name: "apollo", targets: ["apollo"]),
        .executable(name: "apollowm-probe", targets: ["apollowm-probe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "ApolloBase"),
        .target(name: "ApolloKDL", dependencies: ["ApolloBase"]),
        .target(name: "ApolloShellCore"),
        .target(name: "ApolloConfig", dependencies: ["ApolloBase", "ApolloKDL", "ApolloShellCore"]),
        .target(name: "ApolloStyle", dependencies: ["ApolloBase", "ApolloShellCore"]),
        .target(name: "ApolloRuntime", dependencies: ["ApolloBase", "ApolloKDL", "ApolloConfig", "ApolloStyle"]),
        .target(name: "ApolloWMCore"),
        .target(name: "ApolloWM", dependencies: ["ApolloWMCore"]),
        .executableTarget(
            name: "ApolloShell",
            dependencies: [
                "ApolloBase", "ApolloKDL", "ApolloShellCore", "ApolloConfig", "ApolloStyle", "ApolloRuntime", "ApolloWM",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: ["Legacy"]
        ),
        .executableTarget(name: "apollo", dependencies: ["ApolloBase", "ApolloKDL", "ApolloConfig", "ApolloStyle"]),
        .executableTarget(name: "apollowm-probe", dependencies: ["ApolloWM"]),
        .testTarget(name: "ApolloBaseTests", dependencies: ["ApolloBase"]),
        .testTarget(name: "ApolloKDLTests", dependencies: ["ApolloKDL"]),
        .testTarget(name: "ApolloShellCoreTests", dependencies: ["ApolloShellCore"]),
        .testTarget(name: "ApolloConfigTests", dependencies: ["ApolloConfig"]),
        .testTarget(name: "ApolloStyleTests", dependencies: ["ApolloStyle"]),
        .testTarget(name: "ApolloRuntimeTests", dependencies: ["ApolloRuntime"]),
        .testTarget(name: "ApolloWMCoreTests", dependencies: ["ApolloWMCore"]),
        .testTarget(name: "ApolloShellTests", dependencies: ["ApolloShell", "ApolloBase"]),
    ]
)
