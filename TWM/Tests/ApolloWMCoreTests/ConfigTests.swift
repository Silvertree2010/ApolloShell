import CoreGraphics
import Testing
@testable import ApolloWMCore

@Suite("Config file: commands, keys, rules")
struct ConfigTests {
    @Test func everyDefaultCommandReadsBackFromItsText() {
        for command in Command.defaultBindings.values {
            #expect(Command(parsing: command.text) == command)
        }
        for command: Command in [.sendToDesktop(3), .grow(CGSize(width: 0, height: -0.03)), .cycleTab(false)] {
            #expect(Command(parsing: command.text) == command)
        }
    }

    @Test func commandsRejectNonsense() {
        #expect(Command(parsing: "focus sideways") == nil)
        #expect(Command(parsing: "send 12") == nil)
        #expect(Command(parsing: "float now") == nil)
        #expect(Command(parsing: "grow 5 0") == nil)
        #expect(Command(parsing: "") == nil)
    }

    @Test func commandsIgnoreCaseAndSpacing() {
        #expect(Command(parsing: "  Focus   LEFT ") == .focus(.left))
    }

    @Test func bindReplacesAndUnbindRemovesADefault() {
        let config = TWMConfig.parse("""
        bind = H, focus left   # vim style
        unbind = q
        bind = F5, send 2
        """)
        #expect(config.problems.isEmpty)
        #expect(config.bindings[KeyNames.code("h")!] == .focus(.left))
        #expect(config.bindings[KeyNames.code("q")!] == nil)
        #expect(config.bindings[KeyNames.code("f5")!] == .sendToDesktop(2))
        #expect(config.bindings[KeyNames.code("f")!] == .toggleFullscreen)
    }

    @Test func badLinesAreReportedWithTheirNumberAndSkipped() {
        let config = TWMConfig.parse("""
        # comment

        bind = nokey, float
        bind = x, dance
        wat
        rule = explode, app:Finder
        rule = float
        bind = x, float
        """)
        #expect(config.problems.count == 5)
        #expect(config.problems[0].hasPrefix("line 3:"))
        #expect(config.problems[4].hasPrefix("line 7:"))
        #expect(config.bindings[KeyNames.code("x")!] == .toggleFloating)
    }

    @Test func rulesMatchBundleIDOrNameAndTitlePart() {
        let config = TWMConfig.parse("""
        rule = float, app:com.apple.calculator
        rule = ignore, app:zoom.us, title:meeting
        rule = tile, title:Inspector
        """)
        #expect(config.problems.isEmpty)
        let rules = config.rules
        #expect(rules.action(bundleID: "com.apple.Calculator", appName: "Calculator", title: "") == .float)
        #expect(rules.action(bundleID: "us.zoom.xos", appName: "zoom.us", title: "Zoom Meeting") == .ignore)
        #expect(rules.action(bundleID: "us.zoom.xos", appName: "zoom.us", title: "Settings") == nil)
        #expect(rules.action(bundleID: "x", appName: "Safari", title: "Web Inspector") == .tile)
    }

    @Test func laterRulesWin() {
        let rules = TWMConfig.parse("""
        rule = float, app:Finder
        rule = tile, app:Finder, title:Downloads
        """).rules
        #expect(rules.action(bundleID: nil, appName: "Finder", title: "Downloads") == .tile)
        #expect(rules.action(bundleID: nil, appName: "Finder", title: "Desktop") == .float)
    }

    @Test func templateParsesToTheDefaults() {
        let config = TWMConfig.parse(TWMConfig.template)
        #expect(config.problems.isEmpty)
        #expect(config == TWMConfig())
        // Every default is listed in it.
        let listed = TWMConfig.parse(TWMConfig.template.replacingOccurrences(of: "# bind = ", with: "bind = "))
        #expect(listed.problems.isEmpty)
        #expect(listed.bindings == Command.defaultBindings)
    }
}
