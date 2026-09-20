import Foundation
import Testing
@testable import ApolloShellCore

/// A space dictionary as from CGSCopyManagedDisplaySpaces.
private func space(_ id: Int, type: Int = 0) -> [String: Any] {
    ["ManagedSpaceID": id, "id64": id, "type": type, "uuid": ""]
}

private func display(_ identifier: String, spaces: [[String: Any]], current: Int) -> [String: Any] {
    // As measured: the active space carries its own type.
    let type = spaces.first { ($0["id64"] as? Int) == current }?["type"] as? Int ?? 0
    return ["Display Identifier": identifier, "Spaces": spaces, "Current Space": space(current, type: type)]
}

private let mainUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

@Suite("Spaces from SkyLight")
struct SpaceListTests {
    @Test("shape measured on 14.09.: order like Mission Control, not by identifier")
    func measuredShape() {
        let displays = [display(mainUUID, spaces: [space(3), space(1)], current: 1)]
        let snapshot = SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)
        #expect(snapshot == SpaceSnapshot(desktops: [3, 1], activeIndex: 1))
    }

    @Test("four desktops, the second one active")
    func fourDesktops() {
        let displays = [display(mainUUID, spaces: [space(1), space(2), space(5), space(9)], current: 2)]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)?.activeIndex == 1)
    }

    @Test("fullscreen spaces do not count")
    func skipsFullscreen() {
        let displays = [display(mainUUID, spaces: [space(1), space(6, type: 4), space(7)], current: 7)]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)
            == SpaceSnapshot(desktops: [1, 7], activeIndex: 1))
    }

    @Test("fullscreen space active: no active dot")
    func fullscreenActive() {
        let displays = [display(mainUUID, spaces: [space(1), space(6, type: 4)], current: 6)]
        let snapshot = SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)
        #expect(snapshot?.desktops == [1])
        #expect(snapshot?.activeIndex == nil)
    }

    @Test("two screens: the main screen by UUID, case does not matter")
    func picksMainDisplay() {
        let displays = [
            display("AAAA-OTHER", spaces: [space(10), space(11)], current: 11),
            display(mainUUID, spaces: [space(1), space(2), space(3)], current: 3),
        ]
        let snapshot = SpaceList.snapshot(displays: displays, mainDisplay: mainUUID.lowercased())
        #expect(snapshot == SpaceSnapshot(desktops: [1, 2, 3], activeIndex: 2))
    }

    @Test("shared spaces are named \"Main\"")
    func sharedSpaces() {
        let displays = [display("Main", spaces: [space(1), space(4)], current: 4)]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)?.activeIndex == 1)
    }

    @Test("identifier falls back to ManagedSpaceID if needed")
    func managedSpaceIDFallback() {
        let spaces: [[String: Any]] = [["ManagedSpaceID": 8, "type": 0]]
        let displays: [[String: Any]] = [["Display Identifier": "Main", "Spaces": spaces, "Current Space": ["ManagedSpaceID": 8]]]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: nil) == SpaceSnapshot(desktops: [8], activeIndex: 0))
    }

    @Test("no type, no dot")
    func missingTypeSkipped() {
        let spaces: [[String: Any]] = [["id64": 1], space(2)]
        let displays: [[String: Any]] = [["Display Identifier": "Main", "Spaces": spaces, "Current Space": space(2)]]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: nil) == SpaceSnapshot(desktops: [2], activeIndex: 0))
    }

    @Test("nothing usable: no snapshot")
    func garbage() {
        #expect(SpaceList.snapshot(displays: [], mainDisplay: mainUUID) == nil)
        #expect(SpaceList.snapshot(displays: [["Display Identifier": "Main"]], mainDisplay: nil) == nil)
        let onlyFullscreen = [display("Main", spaces: [space(6, type: 4)], current: 6)]
        #expect(SpaceList.snapshot(displays: onlyFullscreen, mainDisplay: nil) == nil)
    }
}

@Suite("Fullscreen per screen from SkyLight")
struct FullscreenDisplaysTests {
    private let otherUUID = "AAAA-OTHER"

    @Test("fullscreen space active: this screen, uppercased")
    func fullscreenActive() {
        let displays = [
            display(mainUUID.lowercased(), spaces: [space(1), space(6, type: 4)], current: 6),
            display(otherUUID, spaces: [space(10)], current: 10),
        ]
        #expect(SpaceList.fullscreenDisplays(displays) == [mainUUID])
    }

    @Test("fullscreen on another desktop, but a desktop active here: nothing")
    func fullscreenElsewhere() {
        let displays = [display(mainUUID, spaces: [space(1), space(6, type: 4)], current: 1)]
        #expect(SpaceList.fullscreenDisplays(displays) == [])
    }

    @Test("two screens, both in fullscreen")
    func bothFullscreen() {
        let displays = [
            display(mainUUID, spaces: [space(1), space(6, type: 4)], current: 6),
            display(otherUUID, spaces: [space(10), space(12, type: 4)], current: 12),
        ]
        #expect(SpaceList.fullscreenDisplays(displays) == [mainUUID, otherUUID])
    }

    @Test("type missing on the current space: look it up in the list")
    func typeFromList() {
        let displays: [[String: Any]] = [[
            "Display Identifier": mainUUID,
            "Spaces": [space(1), space(6, type: 4)],
            "Current Space": ["id64": 6],
        ]]
        #expect(SpaceList.fullscreenDisplays(displays) == [mainUUID])
    }

    @Test("shared spaces report \"Main\"")
    func shared() {
        let displays = [display("Main", spaces: [space(1), space(6, type: 4)], current: 6)]
        #expect(SpaceList.fullscreenDisplays(displays) == [SpaceList.sharedDisplayIdentifier.uppercased()])
    }

    @Test("nothing readable: nil, so the old state stays")
    func unreadable() {
        #expect(SpaceList.fullscreenDisplays([]) == nil)
        #expect(SpaceList.fullscreenDisplays([["Spaces": [space(1)]]]) == nil)
    }
}
