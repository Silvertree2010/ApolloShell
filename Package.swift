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
    dependencies: [
        // Selbstaktualisierung (nur fuer die DMG-Fassung; die
        // Homebrew-Fassung schaltet sie zur Laufzeit ab). Feste Fassung:
        // ein Update-Rahmenwerk soll sich nie unbemerkt aendern.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Reine Logik ohne Oberflaeche, getestet. Bleibt ohne Abhaengigkeiten.
        .target(name: "ApolloShellCore"),
        // Die App: Leiste, Launcher, Kantenfenster.
        .executableTarget(name: "ApolloShell", dependencies: [
            "ApolloShellCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ]),
        .testTarget(name: "ApolloShellCoreTests", dependencies: ["ApolloShellCore"]),
    ]
)
