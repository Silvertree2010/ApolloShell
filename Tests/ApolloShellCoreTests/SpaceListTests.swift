import Foundation
import Testing
@testable import ApolloShellCore

/// Ein Space-Woerterbuch wie von CGSCopyManagedDisplaySpaces.
private func space(_ id: Int, type: Int = 0) -> [String: Any] {
    ["ManagedSpaceID": id, "id64": id, "type": type, "uuid": ""]
}

private func display(_ identifier: String, spaces: [[String: Any]], current: Int) -> [String: Any] {
    ["Display Identifier": identifier, "Spaces": spaces, "Current Space": space(current)]
}

private let mainUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

@Suite("Spaces aus SkyLight")
struct SpaceListTests {
    @Test("gemessene Form vom 14.09.: Reihenfolge wie Mission Control, nicht nach Kennung")
    func measuredShape() {
        let displays = [display(mainUUID, spaces: [space(3), space(1)], current: 1)]
        let snapshot = SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)
        #expect(snapshot == SpaceSnapshot(desktops: [3, 1], activeIndex: 1))
    }

    @Test("vier Schreibtische, der zweite aktiv")
    func fourDesktops() {
        let displays = [display(mainUUID, spaces: [space(1), space(2), space(5), space(9)], current: 2)]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)?.activeIndex == 1)
    }

    @Test("Vollbild-Spaces zaehlen nicht mit")
    func skipsFullscreen() {
        let displays = [display(mainUUID, spaces: [space(1), space(6, type: 4), space(7)], current: 7)]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)
            == SpaceSnapshot(desktops: [1, 7], activeIndex: 1))
    }

    @Test("Vollbild-Space aktiv: kein aktiver Punkt")
    func fullscreenActive() {
        let displays = [display(mainUUID, spaces: [space(1), space(6, type: 4)], current: 6)]
        let snapshot = SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)
        #expect(snapshot?.desktops == [1])
        #expect(snapshot?.activeIndex == nil)
    }

    @Test("zwei Bildschirme: der Hauptbildschirm nach UUID, Gross/klein egal")
    func picksMainDisplay() {
        let displays = [
            display("AAAA-OTHER", spaces: [space(10), space(11)], current: 11),
            display(mainUUID, spaces: [space(1), space(2), space(3)], current: 3),
        ]
        let snapshot = SpaceList.snapshot(displays: displays, mainDisplay: mainUUID.lowercased())
        #expect(snapshot == SpaceSnapshot(desktops: [1, 2, 3], activeIndex: 2))
    }

    @Test("gemeinsame Spaces heissen \"Main\"")
    func sharedSpaces() {
        let displays = [display("Main", spaces: [space(1), space(4)], current: 4)]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: mainUUID)?.activeIndex == 1)
    }

    @Test("Kennung notfalls aus ManagedSpaceID")
    func managedSpaceIDFallback() {
        let spaces: [[String: Any]] = [["ManagedSpaceID": 8, "type": 0]]
        let displays: [[String: Any]] = [["Display Identifier": "Main", "Spaces": spaces, "Current Space": ["ManagedSpaceID": 8]]]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: nil) == SpaceSnapshot(desktops: [8], activeIndex: 0))
    }

    @Test("ohne type kein Punkt")
    func missingTypeSkipped() {
        let spaces: [[String: Any]] = [["id64": 1], space(2)]
        let displays: [[String: Any]] = [["Display Identifier": "Main", "Spaces": spaces, "Current Space": space(2)]]
        #expect(SpaceList.snapshot(displays: displays, mainDisplay: nil) == SpaceSnapshot(desktops: [2], activeIndex: 0))
    }

    @Test("nichts Brauchbares: keine Kapsel")
    func garbage() {
        #expect(SpaceList.snapshot(displays: [], mainDisplay: mainUUID) == nil)
        #expect(SpaceList.snapshot(displays: [["Display Identifier": "Main"]], mainDisplay: nil) == nil)
        let onlyFullscreen = [display("Main", spaces: [space(6, type: 4)], current: 6)]
        #expect(SpaceList.snapshot(displays: onlyFullscreen, mainDisplay: nil) == nil)
    }
}
