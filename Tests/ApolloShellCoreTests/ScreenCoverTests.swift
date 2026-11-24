import CoreGraphics
import Testing
@testable import ApolloShellCore

struct ScreenCoverTests {
    let main = ScreenCover.Screen(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117))
    let side = ScreenCover.Screen(id: 2, frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440))
    let own: Int32 = 1

    func window(_ pid: Int32, _ frame: CGRect, owner: String = "Game", layer: Int = 0, alpha: Double = 1) -> ScreenCover.Window {
        .init(pid: pid, owner: owner, layer: layer, alpha: alpha, bounds: frame)
    }

    func covered(_ windows: [ScreenCover.Window], front: Int32? = 50) -> Set<UInt32> {
        ScreenCover.coveredScreens(windows: windows, screens: [main, side], frontPID: front, ownPID: own)
    }

    @Test func borderlessWindowAtNormalLevel() {
        #expect(covered([window(50, main.frame)]) == [1])
    }

    @Test func borderlessWindowCountsOnlyOnItsScreen() {
        #expect(covered([window(50, side.frame)]) == [2])
    }

    @Test func windowOnePointLargerStillCovers() {
        #expect(covered([window(50, main.frame.insetBy(dx: -1, dy: -1))]) == [1])
    }

    @Test func zoomedWindowBelowMenuBarDoesNot() {
        #expect(covered([window(50, CGRect(x: 0, y: 33, width: 1728, height: 1084))]).isEmpty)
    }

    @Test func exclusiveFullscreenAtShieldingLevel() {
        #expect(covered([window(50, main.frame, layer: 2_147_483_628)]) == [1])
    }

    @Test func borderlessAtMenuLevelOfFrontApp() {
        #expect(covered([window(50, main.frame, layer: 25)]) == [1])
    }

    @Test func overlayOfBackgroundToolDoesNot() {
        #expect(covered([window(60, main.frame, owner: "ClawdCrab", layer: 25)], front: 50).isEmpty)
    }

    @Test func overlayInFrontOfGameDoesNotHideGame() {
        let windows = [window(60, main.frame, owner: "ClawdCrab", layer: 25), window(50, main.frame)]
        #expect(covered(windows, front: 50) == [1])
    }

    @Test func gameBehindAnotherAppsWindowDoesNot() {
        let windows = [window(70, CGRect(x: 200, y: 200, width: 800, height: 600), owner: "Finder"), window(50, main.frame)]
        #expect(covered(windows, front: 70).isEmpty)
    }

    @Test func gamesOwnDialogInFrontStillCounts() {
        let windows = [window(50, CGRect(x: 600, y: 400, width: 400, height: 200)), window(50, main.frame)]
        #expect(covered(windows) == [1])
    }

    @Test func windowOnOtherScreenDoesNotBlock() {
        let windows = [window(70, CGRect(x: 200, y: 200, width: 800, height: 600), owner: "Finder"), window(50, side.frame)]
        #expect(covered(windows, front: 70) == [2])
    }

    @Test func smallFloatingPanelInFrontDoesNotBlock() {
        let windows = [window(70, CGRect(x: 10, y: 10, width: 200, height: 200), owner: "Notes", layer: 3), window(50, main.frame)]
        #expect(covered(windows, front: 70) == [1])
    }

    @Test func ownAndSystemWindowsNeverCount() {
        let windows = [
            window(own, main.frame, owner: "ApolloShell"),
            window(80, main.frame, owner: "Dock", layer: 20),
            window(81, main.frame, owner: "Window Server", layer: 25),
            window(82, main.frame, owner: "WindowManager"),
        ]
        #expect(covered(windows, front: 80).isEmpty)
    }

    @Test func invisibleAndDesktopWindowsDoNot() {
        let windows = [window(50, main.frame, alpha: 0), window(51, main.frame, owner: "Finder", layer: -2_147_483_603)]
        #expect(covered(windows, front: 51).isEmpty)
    }

    @Test func readsWindowList() {
        let list: [[String: Any]] = [
            [kCGWindowOwnerPID as String: 50, kCGWindowOwnerName as String: "Game", kCGWindowLayer as String: 25,
             kCGWindowAlpha as String: 1.0,
             kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 1728, "Height": 1117]],
            [kCGWindowOwnerName as String: "no pid"],
        ]
        #expect(ScreenCover.windows(list) == [window(50, main.frame, layer: 25)])
    }
}
