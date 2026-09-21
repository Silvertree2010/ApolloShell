// swift-tools-version: 6.2
import PackageDescription

// ApolloShell: a macOS desktop shell modeled after Caelestia
// (Hyprland) - bar with Dock, launcher, dashboard, edge windows.
// Was called "Launcher" until 14.09.2026.
let package = Package(
    name: "ApolloShell",
    // Liquid Glass (NSGlassEffectView) only exists starting with macOS 26.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ApolloShell", targets: ["ApolloShell"]),
    ],
    dependencies: [
        // Self-updating (only for the DMG build; the Homebrew build
        // disables it at runtime). Pinned version: an update framework
        // should never change unnoticed.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        // ApolloShell-TWM: the tiling window manager, a package of its own
        // in TWM/ (merged with its history via git subtree).
        .package(path: "TWM"),
    ],
    targets: [
        // Pure logic without UI, tested. Stays free of dependencies.
        .target(name: "ApolloShellCore"),
        // The app: bar, launcher, edge windows.
        .executableTarget(name: "ApolloShell", dependencies: [
            "ApolloShellCore",
            .product(name: "Sparkle", package: "Sparkle"),
            .product(name: "ApolloWM", package: "TWM"),
        ]),
        .testTarget(name: "ApolloShellCoreTests", dependencies: ["ApolloShellCore"]),
    ]
)
