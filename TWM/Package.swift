// swift-tools-version: 6.2
import PackageDescription

// ApolloWM: a tiling window manager framework for macOS, modeled on Hyprland.
// Headless by design: it arranges, moves and animates windows. Any visible UI
// (bars, menus, overlays) belongs to the host, e.g. ApolloShell.
let package = Package(
    name: "ApolloWM",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ApolloWM", targets: ["ApolloWM"]),
        .executable(name: "apollowm-probe", targets: ["apollowm-probe"]),
    ],
    targets: [
        // Pure logic (layout, springs, stats). No AppKit, fully tested.
        .target(name: "ApolloWMCore"),
        // macOS glue: Accessibility windows, mouse tracking, animation loop.
        .target(name: "ApolloWM", dependencies: ["ApolloWMCore"]),
        // Measurement tool for the drag-and-glide spike.
        .executableTarget(name: "apollowm-probe", dependencies: ["ApolloWM"]),
        .testTarget(name: "ApolloWMCoreTests", dependencies: ["ApolloWMCore"]),
    ]
)
