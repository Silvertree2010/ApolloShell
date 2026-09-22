import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus > TWM: tiling window manager settings")
struct TWMSettingsTests {
    @Test("off by default, also for files from before the TWM")
    func offByDefault() {
        #expect(!ShellSettings.load(from: nil).twm.enabled)
        #expect(ShellSettings.load(from: Data("{}".utf8)).twm == TWMSettings())
    }

    @Test("one key read, the rest default; wrong types ignored", arguments: [
        (#"{"twm":{"enabled":true}}"#, { var s = TWMSettings(); s.enabled = true; return s }()),
        (#"{"twm":{"resize":"snap","innerGap":"wide"}}"#, { var s = TWMSettings(); s.resize = .snap; return s }()),
        (#"{"twm":{"resize":"wobbly"}}"#, TWMSettings()),
        (#"{"twm":5}"#, TWMSettings()),
    ])
    func partial(json: String, expected: TWMSettings) {
        #expect(ShellSettings.load(from: Data(json.utf8)).twm == expected)
    }

    @Test("out-of-range values are clamped")
    func clamped() {
        let json = #"{"twm":{"focusDelayMilliseconds":9000,"innerGap":-4,"outerGap":100,"glideDuration":0}}"#
        let twm = ShellSettings.load(from: Data(json.utf8)).twm
        #expect(twm.focusDelayMilliseconds == 500)
        #expect(twm.innerGap == 0)
        #expect(twm.outerGap == 40)
        #expect(twm.glideDuration == 0.1)
    }

    @Test("the newer settings are read and clamped too")
    func newerSettings() {
        let json = #"{"twm":{"tabBarHeight":200,"resizeStep":0,"modeTimeout":99,"scratchpadShare":2,"appleDesktops":false,"terminal":"com.mitchellh.ghostty"}}"#
        let twm = ShellSettings.load(from: Data(json.utf8)).twm
        #expect(twm.tabBarHeight == 48)
        #expect(twm.resizeStep == 0.01)
        #expect(twm.modeTimeout == 20)
        #expect(twm.scratchpadShare == 0.95)
        #expect(!twm.appleDesktops)
        #expect(twm.quitWithLastWindow)
        #expect(twm.terminal == "com.mitchellh.ghostty")
    }

    @Test("the canvas settings are read and clamped")
    func canvasSettings() {
        let json = #"{"twm":{"layout":"canvas","columnWidth":9,"scrollSpeed":0,"centerFocusedColumn":true,"invertScroll":true}}"#
        let twm = ShellSettings.load(from: Data(json.utf8)).twm
        #expect(twm.layout == .canvas)
        #expect(twm.columnWidth == 1)
        #expect(twm.scrollSpeed == 0.5)
        #expect(twm.centerFocusedColumn)
        #expect(twm.invertScroll)
        #expect(twm.scrollPans)
        #expect(ShellSettings.load(from: Data(#"{"twm":{"layout":"spiral"}}"#.utf8)).twm.layout == .dwindle)
    }

    @Test("round trip and readable keys")
    func roundTrip() {
        var settings = ShellSettings()
        settings.twm.enabled = true
        settings.twm.resize = .smooth
        settings.twm.focusDelayMilliseconds = 80
        #expect(ShellSettings.load(from: settings.encoded()) == settings)
        let text = String(decoding: settings.encoded(), as: UTF8.self)
        for key in ["\"twm\"", "\"enabled\"", "\"focusFollowsMouse\"", "\"focusDelayMilliseconds\"", "\"resize\""] {
            #expect(text.contains(key))
        }
    }
}
