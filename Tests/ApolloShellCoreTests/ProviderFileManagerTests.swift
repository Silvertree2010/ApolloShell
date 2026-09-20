import Foundation
import Testing
@testable import ApolloShellCore

@Suite("File manager at the top of the Dock")
struct ProviderFileManagerTests {
    @Test("setting, otherwise ForkLift, otherwise Finder", arguments: [
        (Optional("org.yanex.marta"), ["org.yanex.marta", "com.binarynights.ForkLift"], "org.yanex.marta"),
        (nil, ["com.binarynights.ForkLift"], "com.binarynights.ForkLift"),
        (nil, [], "com.apple.finder"),
        ("com.apple.finder", ["com.binarynights.ForkLift"], "com.apple.finder"),
        ("com.apple.finder", [], "com.apple.finder"),
        ("org.yanex.marta", ["com.binarynights.ForkLift"], "com.binarynights.ForkLift"),
        ("org.yanex.marta", [], "com.apple.finder"),
    ])
    func resolve(setting: String?, installed: [String], expected: String) {
        #expect(ProviderFileManager.resolve(setting: setting) { installed.contains($0) } == expected)
    }

    @Test("hide Finder only when another one replaces it")
    func hidden() {
        #expect(ProviderFileManager.hidden(for: "com.apple.finder").isEmpty)
        #expect(ProviderFileManager.hidden(for: "com.binarynights.ForkLift") == ["com.apple.finder"])
        #expect(ProviderFileManager.hidden(for: "org.yanex.marta") == ["com.apple.finder"])
    }

    @Test("reveal: select only via the system's file viewer, otherwise the folder with the app", arguments: [
        ("com.apple.finder", Optional<String>.none, Optional<String>.none),
        ("com.apple.finder", "", nil),
        ("com.apple.finder", "com.binarynights.ForkLift", "com.apple.finder"),
        ("com.binarynights.ForkLift", "com.binarynights.ForkLift", nil),
        ("com.binarynights.ForkLift", "com.binarynights.forklift", nil),
        ("com.binarynights.ForkLift", nil, "com.binarynights.ForkLift"),
        ("org.yanex.marta", "com.binarynights.ForkLift", "org.yanex.marta"),
    ])
    func reveal(fileManager: String, systemViewer: String?, openWith: String?) {
        let expected: ProviderFileManager.Reveal = openWith.map { .openFolder(bundleID: $0) } ?? .selectInFileViewer
        #expect(ProviderFileManager.reveal(fileManager: fileManager, systemFileViewer: systemViewer) == expected)
    }

    @Test("choices in Nexus: Finder, installed known ones, then its own", arguments: [
        (Optional<String>.none, ["com.binarynights.ForkLift"], ["com.apple.finder", "com.binarynights.ForkLift"]),
        (nil, [], ["com.apple.finder"]),
        ("com.example.Files", ["org.yanex.marta", "com.cocoatech.PathFinder"],
         ["com.apple.finder", "com.cocoatech.PathFinder", "org.yanex.marta", "com.example.Files"]),
        ("org.yanex.marta", ["org.yanex.marta"], ["com.apple.finder", "org.yanex.marta"]),
        ("com.apple.finder", [], ["com.apple.finder"]),
    ])
    func choices(setting: String?, installed: [String], expected: [String]) {
        #expect(ProviderFileManager.choices(setting: setting) { installed.contains($0) } == expected)
    }

    @Test("known list: ForkLift first, none duplicated, Finder not in it")
    func known() {
        #expect(ProviderFileManager.known.first == AppleDockPrefs.forkLift)
        #expect(Set(ProviderFileManager.known).count == ProviderFileManager.known.count)
        #expect(!ProviderFileManager.known.contains(ProviderFileManager.finder))
    }

    @Test("Dock with a chosen app: on top with a dot, running Finder doesn't come back")
    func dockWithChosenApp() {
        let tiles: [Any] = [
            ["tile-data": ["bundle-identifier": "com.apple.finder"]],
            ["tile-data": ["bundle-identifier": "com.apple.Safari"]],
        ]
        let installed: Set = ["org.yanex.marta", "com.apple.Safari", "com.binarynights.ForkLift"]
        let fileManager = ProviderFileManager.resolve(setting: "org.yanex.marta") { installed.contains($0) }
        let slots = DockLayout.slots(
            pinned: AppleDockPrefs.pinnedBundleIDs(tiles, fileManager: fileManager),
            running: ["com.apple.finder", "com.binarynights.ForkLift"],
            hidden: ProviderFileManager.hidden(for: fileManager),
            alwaysRunning: [fileManager]
        ) { _ in true }
        #expect(slots.map(\.bundleID) == ["org.yanex.marta", "com.apple.Safari", "com.binarynights.ForkLift"])
        #expect(slots[0].pinned && slots[0].running)
        #expect(!slots[1].running && slots[2].running && !slots[2].pinned)
    }

    @Test("Finder chosen, ForkLift installed: Finder on top, ForkLift an ordinary app")
    func dockWithFinder() {
        let installed: Set = ["com.binarynights.ForkLift"]
        let fileManager = ProviderFileManager.resolve(setting: "com.apple.finder") { installed.contains($0) }
        let slots = DockLayout.slots(
            pinned: AppleDockPrefs.pinnedBundleIDs([], fileManager: fileManager),
            running: ["com.binarynights.ForkLift"],
            hidden: ProviderFileManager.hidden(for: fileManager),
            alwaysRunning: [fileManager]
        ) { _ in true }
        #expect(slots.map(\.bundleID) == ["com.apple.finder", "com.binarynights.ForkLift"])
        #expect(slots[0].running && !slots[1].pinned)
    }
}
