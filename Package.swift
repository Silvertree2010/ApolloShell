// swift-tools-version: 6.2
import PackageDescription

// ApolloShell: Desktop-Shell fuer macOS nach dem Vorbild von Caelestia
// (Hyprland) - Leiste mit Dock, Launcher, Dashboard, Kantenfenster.
// Hiess bis 14.09.2026 "Launcher".
let package = Package(
    name: "ApolloShell",
    // Liquid Glass (NSGlassEffectView) gibt es erst ab macOS 26.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ApolloShell", targets: ["ApolloShell"]),
    ],
    targets: [
        // Reine Logik ohne Oberflaeche, getestet.
        .target(name: "ApolloShellCore"),
        // Die App: Leiste, Launcher, Kantenfenster.
        .executableTarget(name: "ApolloShell", dependencies: ["ApolloShellCore"]),
        .testTarget(name: "ApolloShellCoreTests", dependencies: ["ApolloShellCore"]),
    ]
)
