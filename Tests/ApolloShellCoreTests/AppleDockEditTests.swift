import Foundation
import ApolloShellCore
import Testing

@Suite("Changing Apple's Dock list")
struct AppleDockEditTests {
    private func tiles(_ ids: [String]) -> [Any] {
        ids.map { ["tile-data": ["bundle-identifier": $0], "GUID": $0.count] as [String: Any] }
    }

    private func ids(_ tiles: [Any]) -> [String] {
        tiles.compactMap(AppleDockPrefs.bundleID(ofTile:))
    }

    private let unused: () -> [String: Any] = { [:] }

    @Test("removing")
    func remove() {
        #expect(ids(AppleDockPrefs.removing("b", from: tiles(["a", "b", "c"]))) == ["a", "c"])
        #expect(ids(AppleDockPrefs.removing("x", from: tiles(["a"]))) == ["a"])
    }

    @Test("moving: before, after, the start, the end")
    func move() {
        let list = tiles(["a", "b", "c", "d"])
        #expect(ids(AppleDockPrefs.placing("d", at: .before("b"), in: list, newTile: unused)) == ["a", "d", "b", "c"])
        #expect(ids(AppleDockPrefs.placing("a", at: .after("c"), in: list, newTile: unused)) == ["b", "c", "a", "d"])
        #expect(ids(AppleDockPrefs.placing("c", at: .start, in: list, newTile: unused)) == ["c", "a", "b", "d"])
        #expect(ids(AppleDockPrefs.placing("a", at: .end, in: list, newTile: unused)) == ["b", "c", "d", "a"])
    }

    @Test("a moved tile stays the same (the GUID is kept)")
    func keepsTile() {
        let moved = AppleDockPrefs.placing("bb", at: .start, in: tiles(["a", "bb"]), newTile: unused)
        #expect((moved.first as? [String: Any])?["GUID"] as? Int == 2)
    }

    @Test("pinning anew: a tile in the format of Apple's Dock")
    func add() {
        // A path that does not exist: the result must not depend on what is
        // installed on this Mac.
        let url = URL(fileURLWithPath: "/Applications/Not Installed \(UUID().uuidString).app")
        let result = AppleDockPrefs.placing("net.whatsapp.WhatsApp", at: .before("b"), in: tiles(["a", "b"])) {
            AppleDockPrefs.tile(bundleID: "net.whatsapp.WhatsApp", url: url, label: "WhatsApp", guid: 7)
        }
        #expect(ids(result) == ["a", "net.whatsapp.WhatsApp", "b"])
        let tile = result[1] as? [String: Any]
        let data = tile?["tile-data"] as? [String: Any]
        #expect(tile?["tile-type"] as? String == "file-tile")
        #expect(tile?["GUID"] as? Int == 7)
        #expect(data?["file-label"] as? String == "WhatsApp")
        #expect(data?["file-type"] as? Int == 41)
        let urlString = (data?["file-data"] as? [String: Any])?["_CFURLString"] as? String
        #expect(urlString?.hasPrefix("file:///Applications/Not%20Installed%20") == true)
        #expect(urlString?.hasSuffix(".app/") == true)
        // And the bar reads them back correctly.
        #expect(AppleDockPrefs.pinnedBundleIDs(result) == ["com.apple.finder", "a", "net.whatsapp.WhatsApp", "b"])
    }

    @Test("an unknown target: at the end")
    func unknownTarget() {
        #expect(ids(AppleDockPrefs.placing("a", at: .before("zz"), in: tiles(["a", "b"]), newTile: unused)) == ["b", "a"])
    }
}
