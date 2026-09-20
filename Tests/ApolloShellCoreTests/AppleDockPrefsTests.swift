import ApolloShellCore
import Testing

@Suite("Reading Apple's Dock setting")
struct AppleDockPrefsTests {
    @Test("The Finder first, then the tiles in their order")
    func order() {
        let tiles: [Any] = [
            ["tile-data": ["bundle-identifier": "net.kovidgoyal.kitty", "file-label": "kitty"]],
            ["tile-data": ["bundle-identifier": "com.vivaldi.Vivaldi"]],
        ]
        #expect(AppleDockPrefs.pinnedBundleIDs(tiles) == ["com.apple.finder", "net.kovidgoyal.kitty", "com.vivaldi.Vivaldi"])
    }

    @Test("Tiles without a bundle ID or broken: they fall away, the Finder only once")
    func robust() {
        let tiles: [Any] = [
            ["tile-data": ["file-label": "loses Programm"]],
            "kaputt",
            ["tile-data": ["bundle-identifier": "com.apple.finder"]],
            ["tile-data": ["bundle-identifier": "md.obsidian"]],
        ]
        #expect(AppleDockPrefs.pinnedBundleIDs(tiles) == ["com.apple.finder", "md.obsidian"])
    }

    @Test("ForkLift at the Finder's place, the Finder falls out of the pins")
    func fileManager() {
        let tiles: [Any] = [
            ["tile-data": ["bundle-identifier": "com.apple.finder"]],
            ["tile-data": ["bundle-identifier": "net.kovidgoyal.kitty"]],
            ["tile-data": ["bundle-identifier": "com.binarynights.ForkLift"]],
        ]
        #expect(AppleDockPrefs.pinnedBundleIDs(tiles, fileManager: AppleDockPrefs.forkLift)
            == ["com.binarynights.ForkLift", "net.kovidgoyal.kitty"])
    }

    @Test("empty: only the Finder")
    func empty() {
        #expect(AppleDockPrefs.pinnedBundleIDs([]) == ["com.apple.finder"])
    }
}
