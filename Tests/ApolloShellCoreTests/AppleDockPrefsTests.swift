import ApolloShellCore
import Testing

@Suite("Apples Dock-Einstellung lesen")
struct AppleDockPrefsTests {
    @Test("Finder zuerst, dann die Kacheln in ihrer Reihenfolge")
    func order() {
        let tiles: [Any] = [
            ["tile-data": ["bundle-identifier": "net.kovidgoyal.kitty", "file-label": "kitty"]],
            ["tile-data": ["bundle-identifier": "com.vivaldi.Vivaldi"]],
        ]
        #expect(AppleDockPrefs.pinnedBundleIDs(tiles) == ["com.apple.finder", "net.kovidgoyal.kitty", "com.vivaldi.Vivaldi"])
    }

    @Test("Kacheln ohne Bundle-ID oder kaputt: fallen weg, Finder nur einmal")
    func robust() {
        let tiles: [Any] = [
            ["tile-data": ["file-label": "loses Programm"]],
            "kaputt",
            ["tile-data": ["bundle-identifier": "com.apple.finder"]],
            ["tile-data": ["bundle-identifier": "md.obsidian"]],
        ]
        #expect(AppleDockPrefs.pinnedBundleIDs(tiles) == ["com.apple.finder", "md.obsidian"])
    }

    @Test("ForkLift an Finders Platz, Finder faellt aus den Pins")
    func fileManager() {
        let tiles: [Any] = [
            ["tile-data": ["bundle-identifier": "com.apple.finder"]],
            ["tile-data": ["bundle-identifier": "net.kovidgoyal.kitty"]],
            ["tile-data": ["bundle-identifier": "com.binarynights.ForkLift"]],
        ]
        #expect(AppleDockPrefs.pinnedBundleIDs(tiles, fileManager: AppleDockPrefs.forkLift)
            == ["com.binarynights.ForkLift", "net.kovidgoyal.kitty"])
    }

    @Test("leer: nur Finder")
    func empty() {
        #expect(AppleDockPrefs.pinnedBundleIDs([]) == ["com.apple.finder"])
    }
}
